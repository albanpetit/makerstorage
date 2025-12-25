class OrganizationMembership < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  validates :role, presence: true, inclusion: { in: %w[owner admin member] }
  validates :user_id, uniqueness: { scope: :organization_id }

  validate :organization_must_have_owner, on: :destroy
  validate :organization_must_have_owner_on_role_change, on: :update

  scope :owners, -> { where(role: "owner") }
  scope :admins, -> { where(role: %w[owner admin]) }
  scope :members, -> { where(role: "member") }

  def owner?
    role == "owner"
  end

  def admin?
    role.in?(%w[owner admin])
  end

  def member?
    role == "member"
  end

  private

  def organization_must_have_owner
    if owner? && organization.organization_memberships.owners.count == 1
      errors.add(:base, "Organization must have at least one owner")
      throw :abort
    end
  end

  def organization_must_have_owner_on_role_change
    if role_changed? && role_was == "owner" && organization.organization_memberships.owners.count == 1
      errors.add(:role, "Organization must have at least one owner")
    end
  end
end
