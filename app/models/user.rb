class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :lockable

  has_many :organization_memberships, dependent: :destroy
  # Only active memberships grant access: a deactivated member keeps their
  # membership row (and role) but no longer sees or acts in the organization.
  has_many :active_organization_memberships, -> { active }, class_name: "OrganizationMembership"
  has_many :organizations, through: :active_organization_memberships
  # Rows that merely reference the user as an author keep existing (the ledger
  # and memberships outlive the account) with the reference cleared.
  has_many :stock_movements, dependent: :nullify
  has_many :sent_invitations, class_name: "OrganizationMembership", foreign_key: :invited_by_id,
           inverse_of: :invited_by, dependent: :nullify

  after_create :create_personal_organization

  # Get the user's personal organization (the one auto-created on signup, flagged
  # via the `personal` column). Match on the flag rather than the name string so a
  # renamed org — or a changed firstname — still resolves correctly.
  def personal_organization
    organizations.find_by(personal: true) ||
    organizations.first
  end

  # Get all organizations where the user is an owner
  def organizations_where_owner
    organizations.where(organization_memberships: { role: "owner" })
  end

  # Get all organizations where the user is an admin or owner
  def organizations_where_admin
    organizations.where(organization_memberships: { role: %w[owner admin] })
  end

  # Check if the user is a member of an organization
  def member_of?(organization)
    organizations.include?(organization)
  end

  # Check if the user is a member of an organization by ID (more efficient)
  def member_of_organization?(organization_id)
    active_organization_memberships.exists?(organization_id: organization_id)
  end

  # Check if the user is an owner of an organization
  def owner_of?(organization)
    active_organization_memberships.exists?(organization: organization, role: "owner")
  end

  # Check if the user is an admin of an organization
  def admin_of?(organization)
    active_organization_memberships.exists?(organization: organization, role: %w[owner admin])
  end

  # Check if the user may write in an organization (everyone except viewers)
  def writer_of?(organization)
    active_organization_memberships.exists?(organization: organization, role: %w[owner admin member])
  end

  # Get the user's role in an organization
  def role_in(organization)
    active_organization_memberships.find_by(organization: organization)&.role
  end

  private

  # Automatically create a personal organization when the user is created
  def create_personal_organization
    organization = Organization.create!(
      name: "#{firstname}'s Organization",
      personal: true
    )

    OrganizationMembership.create!(
      user: self,
      organization: organization,
      role: "owner"
    )
  end
end
