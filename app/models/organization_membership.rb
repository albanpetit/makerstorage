class OrganizationMembership < ApplicationRecord
  belongs_to :user
  belongs_to :organization
  belongs_to :invited_by, class_name: "User", optional: true

  validates :role, presence: true, inclusion: { in: %w[owner admin member viewer] }
  validates :user_id, uniqueness: { scope: :organization_id }
  validates :invitation_token, uniqueness: true, allow_nil: true

  before_destroy :organization_must_have_owner
  validate :organization_must_have_owner_on_role_change, on: :update

  scope :owners, -> { where(role: "owner") }
  scope :admins, -> { where(role: %w[owner admin]) }
  scope :viewers, -> { where(role: "viewer") }
  scope :members, -> { where(role: "member") }
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :pending_invitation, -> { where.not(invitation_sent_at: nil).where(invitation_accepted_at: nil) }
  scope :accepted, -> { where.not(invitation_accepted_at: nil) }

  before_create :generate_invitation_token, if: :should_generate_token?

  def owner?
    role == "owner"
  end

  def admin?
    role.in?(%w[owner admin])
  end

  def member?
    role == "member"
  end

  def viewer?
    role == "viewer"
  end

  def active?
    active
  end

  def pending_invitation?
    invitation_sent_at.present? && invitation_accepted_at.nil?
  end

  def accepted?
    invitation_accepted_at.present?
  end

  def accept_invitation!
    update!(invitation_accepted_at: Time.current)
  end

  def deactivate!
    update!(active: false)
  end

  def activate!
    update!(active: true)
  end

  private

  def organization_must_have_owner
    if owner? && organization.organization_memberships.owners.active.count == 1
      errors.add(:base, "Organization must have at least one active owner")
      throw :abort
    end
  end

  def organization_must_have_owner_on_role_change
    if role_changed? && role_was == "owner" && organization.organization_memberships.owners.active.count == 1
      errors.add(:role, "Organization must have at least one active owner")
    end
  end

  def should_generate_token?
    invitation_sent_at.present? && invitation_token.blank?
  end

  def generate_invitation_token
    self.invitation_token = SecureRandom.urlsafe_base64(32)
  end
end
