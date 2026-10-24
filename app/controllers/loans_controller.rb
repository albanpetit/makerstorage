# frozen_string_literal: true

# Lending tools and parts to members (or anyone else, by name): lending takes
# the items out of stock, returns put them back, and overdue loans show up here,
# in the sidebar badge and in the email digest. See Loan.
class LoansController < ApplicationController
  include Auth
  include OptionListSerializers

  # Returned loans listed at most; older ones stay in the movements ledger.
  CLOSED_LIMIT = 200
  FILTERS = %w[open overdue returned all].freeze

  before_action :switch_to_linked_organization, only: :show
  before_action :verify_organization_access
  before_action :verify_organization_writer, only: %i[create update return_items return_all write_off]
  before_action :set_loan, only: %i[show update return_items return_all write_off]

  def index
    filter = FILTERS.include?(params[:filter]) ? params[:filter] : "open"
    mine = params[:mine] == "1"
    today = current_organization.local_date

    scope = current_organization.loans
    scope = scope.where(borrower_id: current_user.id) if mine
    recent_closed = scope.closed.recent.limit(CLOSED_LIMIT)
    loans = case filter
    when "open" then scope.active
    when "overdue" then scope.overdue_on(today)
    when "returned" then scope.where(id: recent_closed.select(:id))
    else scope.active.or(scope.where(id: recent_closed.select(:id)))
    end

    render inertia: "loans/index", props: {
      loans: loans.recent.includes(loan_lines: :part).map { |loan| serialize_loan_summary(loan, today) },
      filter: filter,
      mine: mine,
      counts: {
        open: scope.active.count,
        overdue: scope.overdue_on(today).count,
        returned: scope.closed.count
      },
      members: serialize_members,
      # Every part in stock, for the Lend dialog: loaded when it opens (a
      # partial reload), or right away when "Lend" on a part's sheet opened it.
      parts: params[:part_id].present? ? serialize_lendable_parts : InertiaRails.optional { serialize_lendable_parts },
      default_due_on: (today + current_organization.default_loan_days).iso8601,
      # "Lend" from a part's detail opens the dialog with that part.
      prefill_part_id: params[:part_id].presence&.to_i
    }
  end

  def show
    render inertia: "loans/show", props: {
      loan: serialize_loan(@loan),
      storage_locations: serialize_storage_locations
    }
  end

  def create
    loan = current_organization.loans.new(loan_attributes)
    assign_borrower(loan)

    Array(params.dig(:loan, :lines)).each do |line|
      line = line.permit(:part_id, :storage_location_id, :quantity)
      loan.loan_lines.build(
        part: current_organization.parts.find_by(id: line[:part_id]),
        storage_location: current_organization.storage_locations.find_by(id: line[:storage_location_id]),
        quantity: line[:quantity]
      )
    end

    loan.lend!(user: current_user)
    redirect_to loan_path(loan), notice: t("flash.loans.recorded", reference: loan.reference)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_or_to loans_path, alert: t("flash.loans.not_recorded", errors: loan_error_message(e.record))
  end

  # Due date, contact and notes only: lines change through returns and write-offs.
  def update
    if @loan.update(params.require(:loan).permit(:due_on, :borrower_contact, :notes))
      redirect_to loan_path(@loan), notice: t("flash.loans.updated")
    else
      redirect_to loan_path(@loan), alert: @loan.errors.full_messages.to_sentence
    end
  end

  def return_items
    locations = current_organization.storage_locations
    entries = Array(params[:lines]).map do |entry|
      entry = entry.permit(:line_id, :quantity, :storage_location_id)
      location = entry[:storage_location_id].presence && locations.find_by(id: entry[:storage_location_id])
      { line_id: entry[:line_id], quantity: entry[:quantity], storage_location: location.presence }
    end

    @loan.return_items!(entries, user: current_user)
    redirect_to loan_path(@loan), notice: @loan.closed? ? t("flash.loans.closed") : t("flash.loans.return_recorded")
  rescue Loan::Error, ActiveRecord::RecordInvalid => e
    redirect_to loan_path(@loan), alert: settle_error_message(e)
  end

  def return_all
    @loan.return_all!(user: current_user)
    redirect_to loan_path(@loan), notice: t("flash.loans.closed")
  rescue Loan::Error, ActiveRecord::RecordInvalid => e
    redirect_to loan_path(@loan), alert: settle_error_message(e)
  end

  def write_off
    @loan.write_off!(line_id: params[:line_id], quantity: params[:quantity])
    redirect_to loan_path(@loan), notice: @loan.closed? ? "Written off: loan closed." : "Written off."
  rescue Loan::Error, ActiveRecord::RecordInvalid => e
    redirect_to loan_path(@loan), alert: settle_error_message(e)
  end

  private

  def set_loan
    @loan = current_organization.loans.find(params[:id])
  end

  def loan_attributes
    params.require(:loan).permit(:borrower_name, :borrower_contact, :due_on, :notes)
  end

  # A member is picked by id (their name is copied onto the loan); anyone else
  # is typed in. An id outside the organization's active members is refused.
  def assign_borrower(loan)
    borrower_id = params.dig(:loan, :borrower_id).presence
    return unless borrower_id

    borrower = active_members.find_by(id: borrower_id)
    if borrower
      loan.borrower = borrower
      loan.borrower_name = borrower.display_name
      loan.borrower_contact = borrower.email if loan.borrower_contact.blank?
    else
      loan.borrower_id = borrower_id
    end
  end

  def active_members
    User.where(id: current_organization.organization_memberships.granting_access.select(:user_id))
  end

  def loan_error_message(loan)
    messages = loan.errors.full_messages
    if loan.is_a?(Loan)
      loan.loan_lines.each do |line|
        messages += line.errors.full_messages.map { |message| "#{line.part&.reference || t('flash.loans.item')}: #{message}" }
      end
    elsif loan.is_a?(StockMovement)
      messages = [ t("flash.loans.not_enough_stock", reference: loan.part.reference, zone: loan.storage_location.name) ] if loan.errors.key?(:quantity_delta)
    end
    messages.uniq.to_sentence.presence || t("flash.loans.check_items")
  end

  def settle_error_message(error)
    return error.message if error.is_a?(Loan::Error)

    error.record.errors.full_messages.to_sentence
  end

  def serialize_members
    active_members.order(:firstname, :lastname, :email).map do |user|
      { id: user.id, name: user.display_name, email: user.email }
    end
  end

  # Parts with stock somewhere, with the zones holding it (fullest first), for
  # the lend dialog.
  def serialize_lendable_parts
    cache = StorageLocation.full_path_cache(current_organization.storage_locations)
    current_organization.parts.alphabetical
      .joins(:part_storages).where(part_storages: { quantity: 1.. }).distinct
      .includes(part_storages: :storage_location)
      .map do |part|
        storages = part.part_storages.select { |storage| storage.quantity.positive? }.sort_by { |storage| [ -storage.quantity, storage.id ] }
        {
          id: part.id,
          reference: part.reference,
          ipn: part.ipn,
          name: part.name,
          locations: storages.map do |storage|
            { id: storage.storage_location_id, name: storage.storage_location.full_path(cache: cache), quantity: storage.quantity }
          end
        }
      end
  end

  def serialize_loan_summary(loan, today)
    lines = loan.loan_lines
    {
      id: loan.id,
      reference: loan.reference,
      borrower_name: loan.borrower_name,
      mine: loan.borrower_id == current_user.id,
      status: loan.status(today),
      due_on: loan.due_on&.iso8601,
      days_overdue: loan.days_overdue(today),
      created_at: loan.created_at.iso8601,
      closed_at: loan.closed_at&.iso8601,
      item_count: lines.sum(&:quantity),
      outstanding: lines.sum(&:outstanding_quantity),
      items: lines.map { |line| "#{line.quantity} × #{line.part.name}" }.first(3),
      more_items: [ lines.size - 3, 0 ].max
    }
  end

  def serialize_loan(loan)
    today = current_organization.local_date
    cache = StorageLocation.full_path_cache(current_organization.storage_locations)
    {
      id: loan.id,
      reference: loan.reference,
      borrower_name: loan.borrower_name,
      borrower_contact: loan.borrower_contact,
      borrower_is_member: loan.borrower_id.present?,
      lent_by_name: loan.lent_by&.display_name,
      status: loan.status(today),
      due_on: loan.due_on&.iso8601,
      days_overdue: loan.days_overdue(today),
      notes: loan.notes,
      created_at: loan.created_at.iso8601,
      closed_at: loan.closed_at&.iso8601,
      lines: loan.loan_lines.includes(:part, :storage_location).map do |line|
        {
          id: line.id,
          part: { id: line.part.id, reference: line.part.reference, ipn: line.part.ipn, name: line.part.name },
          storage_location: line.storage_location && { id: line.storage_location.id, name: line.storage_location.full_path(cache: cache) },
          quantity: line.quantity,
          returned_quantity: line.returned_quantity,
          lost_quantity: line.lost_quantity,
          outstanding: line.outstanding_quantity
        }
      end
    }
  end
end
