class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :organization_memberships, dependent: :destroy
  has_many :organizations, through: :organization_memberships

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
    organizations.joins(:organization_memberships)
                 .where(organization_memberships: { role: "owner" })
  end

  # Get all organizations where the user is an admin or owner
  def organizations_where_admin
    organizations.joins(:organization_memberships)
                 .where(organization_memberships: { role: %w[owner admin] })
  end

  # Check if the user is a member of an organization
  def member_of?(organization)
    organizations.include?(organization)
  end

  # Check if the user is a member of an organization by ID (more efficient)
  def member_of_organization?(organization_id)
    organization_memberships.exists?(organization_id: organization_id)
  end

  # Check if the user is an owner of an organization
  def owner_of?(organization)
    organization_memberships.exists?(organization: organization, role: "owner")
  end

  # Check if the user is an admin of an organization
  def admin_of?(organization)
    organization_memberships.exists?(organization: organization, role: %w[owner admin])
  end

  # Check if the user may write in an organization (everyone except viewers)
  def writer_of?(organization)
    organization_memberships.exists?(organization: organization, role: %w[owner admin member])
  end

  # Get the user's role in an organization
  def role_in(organization)
    organization_memberships.find_by(organization: organization)&.role
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
