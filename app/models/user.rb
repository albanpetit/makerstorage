class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :timeoutable, :trackable and :omniauthable
  #
  # :confirmable proves the user owns their email. Invitations are addressed by
  # email, so without it anyone could sign up as an invitee-to-be (or switch
  # their email to one) and accept a role meant for someone else. Unconfirmed
  # accounts still sign in (allow_unconfirmed_access_for = nil); they just can't
  # see or answer invitations. See User.email_verification?.
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :lockable, :confirmable

  # Without a way to send mail (no SMTP), nobody could ever confirm: accounts
  # start out confirmed and email changes apply at once, as before.
  before_create :skip_confirmation!, unless: -> { User.email_verification? }

  has_many :organization_memberships, dependent: :destroy
  # Only active memberships grant access: a deactivated member keeps their
  # membership row (and role) but no longer sees or acts in the organization,
  # and an invitation grants nothing until the invitee accepts it.
  has_many :active_organization_memberships, -> { granting_access }, class_name: "OrganizationMembership"
  # Invitations still open to answer (expired ones are left for an admin to renew).
  has_many :pending_invitations, -> { active.pending_invitation.unexpired_invitation }, class_name: "OrganizationMembership"
  has_many :organizations, through: :active_organization_memberships
  # Access the user granted MCP clients (Claude…), see OauthAuthorization.
  has_many :oauth_authorizations, dependent: :delete_all
  # Rows that merely reference the user as an author keep existing (the ledger
  # and memberships outlive the account) with the reference cleared.
  has_many :stock_movements, dependent: :nullify
  has_many :project_builds, dependent: :nullify
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

  # Whether addresses must be confirmed by mail (config.x.email_verification).
  def self.email_verification?
    Rails.configuration.x.email_verification != false
  end

  # Invitations name an email address, so they're only shown to and answerable
  # by someone who has proven they own it.
  def can_answer_invitations?
    confirmed?
  end

  # Get the user's role in an organization
  def role_in(organization)
    active_organization_memberships.find_by(organization: organization)&.role
  end

  # Devise holds a new sign-in email in unconfirmed_email until it's confirmed;
  # with verification off there's no mail to confirm it with, so apply it now.
  def postpone_email_change?
    User.email_verification? && super
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
