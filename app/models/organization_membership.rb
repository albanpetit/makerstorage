class OrganizationMembership < ApplicationRecord
  belongs_to :user
  belongs_to :organization, inverse_of: :organization_memberships
  belongs_to :invited_by, class_name: "User", optional: true

  ROLES = %w[owner admin member viewer].freeze

  validates :role, presence: true, inclusion: { in: ROLES }
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
  # Memberships that give access: active and not an invitation still awaiting
  # the invitee's answer (memberships created directly carry no invitation).
  scope :granting_access, -> { active.where(invitation_sent_at: nil).or(active.accepted) }

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

  def grants_access?
    active? && !pending_invitation?
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
    # When the organization itself is being deleted, the whole membership set
    # goes with it — the "keep at least one owner" rule doesn't apply.
    return if organization&.being_destroyed
    return unless owner? && grants_access? && no_other_active_owner?

    errors.add(:base, "Organization must have at least one active owner")
    throw :abort
  end

  # Only losing an *active* owner matters: demoting or deactivating an owner who
  # was already inactive (or never accepted the invitation) leaves the active
  # owner count unchanged.
  def organization_must_have_owner_on_role_change
    was_active_owner = role_in_database == "owner" && active_in_database && !pending_invitation?
    return unless was_active_owner && !(owner? && grants_access?) && no_other_active_owner?

    errors.add(role_changed? ? :role : :active, "Organization must have at least one active owner")
  end

  def no_other_active_owner?
    organization.organization_memberships.owners.granting_access.where.not(id: id).none?
  end

  def should_generate_token?
    invitation_sent_at.present? && invitation_token.blank?
  end

  def generate_invitation_token
    self.invitation_token = SecureRandom.urlsafe_base64(32)
  end
end
