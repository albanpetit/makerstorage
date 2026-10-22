# Items lent out of stock: tools or parts handed to a member (or anyone else,
# by name) with an optional due date. Lending takes the items out of stock with
# one "out" movement per line; returns put them back with "in" movements, and
# what never comes back (lost, used up) is written off with no movement, since
# it already left stock. The loan closes once nothing is outstanding.
#
# Overdue is computed from the due date and the organization's local date, never
# stored, so extending a loan or a time zone change needs no bookkeeping.
class Loan < ApplicationRecord
  include GeneratedReference

  class Error < StandardError; end

  # Associations
  belongs_to :organization
  belongs_to :borrower, class_name: "User", optional: true
  belongs_to :lent_by, class_name: "User", optional: true
  has_many :loan_lines, -> { order(:id) }, dependent: :destroy, inverse_of: :loan

  # Constants
  STATUSES = %w[open overdue returned].freeze
  MAX_DAYS = 3650

  # Validations
  validates :borrower_name, presence: true, length: { maximum: 255 }
  validates :borrower_contact, length: { maximum: 255 }
  validates :notes, length: { maximum: 5000 }
  validates :reference, uniqueness: { scope: :organization_id }, allow_blank: true
  validate :borrower_must_be_member, if: -> { borrower_id.present? && will_save_change_to_borrower_id? }
  validate :must_have_lines, on: :create

  # Scopes
  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :active, -> { where(closed_at: nil) }
  scope :closed, -> { where.not(closed_at: nil) }
  scope :overdue_on, ->(date) { active.where(due_on: ...date) }

  # Builds a per-organization-unique reference "LN-YYYYMMDD-N" (mirrors
  # Project.next_reference).
  def self.next_reference(organization, date: Date.current)
    base = "LN-#{date.strftime('%Y%m%d')}"
    reference = "#{base}-1"
    suffix = 1
    while organization.loans.exists?(reference: reference)
      suffix += 1
      reference = "#{base}-#{suffix}"
    end
    reference
  end

  # Methods - Status
  def closed?
    closed_at.present?
  end

  def overdue?(date = organization.local_date)
    !closed? && due_on.present? && due_on < date
  end

  def status(date = organization.local_date)
    return "returned" if closed?

    overdue?(date) ? "overdue" : "open"
  end

  def days_overdue(date = organization.local_date)
    overdue?(date) ? (date - due_on).to_i : 0
  end

  def outstanding_quantity
    loan_lines.sum(&:outstanding_quantity)
  end

  # Methods - Lending
  #
  # Saves the loan with a generated reference and takes every line out of the
  # zone it names, all or nothing: one refused movement (not enough stock)
  # leaves neither the loan nor any movement behind. Raises RecordInvalid.
  def lend!(user:)
    self.lent_by = user
    transaction do
      save_with_generated_reference! { Loan.next_reference(organization) }
      loan_lines.each do |line|
        organization.stock_movements.create!(
          part: line.part, storage_location: line.storage_location, user: user,
          movement_type: "out", quantity_delta: -line.quantity,
          reason: "Lent to #{borrower_name}", reference: reference
        )
      end
    end
    self
  end

  # Methods - Returns
  #
  # Puts items back into stock. +entries+ is a list of { line_id:, quantity:,
  # storage_location: } (the zone defaults to the one the line was taken from,
  # then to the part's first zone). Row-locks the loan and re-reads its lines,
  # so two people returning the same item at once can't both credit it.
  # Raises Loan::Error on a bad entry and RecordInvalid if a movement is refused.
  def return_items!(entries, user:)
    settle!(entries) do |line, quantity, entry|
      location = entry[:storage_location] || line.storage_location || line.part.fallback_storage_location
      raise Error, I18n.t("errors.loans.pick_return_zone", reference: line.part.reference) unless location
      raise Error, I18n.t("errors.loans.zone_other_organization") unless location.organization_id == organization_id

      organization.stock_movements.create!(
        part: line.part, storage_location: location, user: user,
        movement_type: "in", quantity_delta: quantity,
        reason: "Returned by #{borrower_name}", reference: reference
      )
      line.returned_quantity += quantity
    end
  end

  # Everything still out goes back where it was taken from.
  def return_all!(user:)
    entries = loan_lines.reload.select { |line| line.outstanding_quantity.positive? }
      .map { |line| { line_id: line.id, quantity: line.outstanding_quantity } }
    return_items!(entries, user: user)
  end

  # Records items that won't come back (lost, broken, used up). No movement:
  # they already left stock when they were lent.
  def write_off!(line_id:, quantity:)
    settle!([ { line_id: line_id, quantity: quantity } ]) do |line, amount, _entry|
      line.lost_quantity += amount
    end
  end

  private

  def settle!(entries)
    raise Error, I18n.t("errors.loans.closed") if closed?

    with_lock do
      raise Error, I18n.t("errors.loans.closed") if closed?

      lines = loan_lines.reload.to_a
      ActiveRecord::Associations::Preloader.new(records: lines, associations: { part: { part_storages: :storage_location } }).call
      lines = lines.index_by(&:id)
      entries = entries.reject { |entry| entry[:quantity].to_i.zero? }
      raise Error, I18n.t("errors.loans.enter_quantity") if entries.empty?

      entries.each do |entry|
        line = lines[entry[:line_id].to_i]
        quantity = entry[:quantity].to_i
        raise Error, I18n.t("errors.loans.not_on_loan") unless line
        raise Error, I18n.t("errors.loans.positive") unless quantity.positive?
        if quantity > line.outstanding_quantity
          raise Error, I18n.t("errors.loans.only_outstanding", count: line.outstanding_quantity, reference: line.part.reference)
        end

        yield line, quantity, entry
        line.save!
      end

      update!(closed_at: Time.current) if lines.values.all? { |line| line.outstanding_quantity.zero? }
    end
    self
  end

  def borrower_must_be_member
    unless organization && borrower&.member_of_organization?(organization_id)
      errors.add(:borrower, :organization_member)
    end
  end

  def must_have_lines
    errors.add(:base, :no_loan_lines) if loan_lines.empty?
  end
end
