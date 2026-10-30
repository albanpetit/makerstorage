require "test_helper"

class UserAccountDeletionTest < ActiveSupport::TestCase
  setup do
    @user = create_user(firstname: "Ada", lastname: "Lovelace")
    @personal = @user.personal_organization
  end

  def add_member(org, user, role: "member")
    OrganizationMembership.create!(organization: org, user: user, role: role)
  end

  def loan_for(org, **attrs)
    Loan.new(organization: org, borrower_name: "Someone", **attrs).tap { |loan| loan.save!(validate: false) }
  end

  test "deletes the account with the organizations nobody else uses" do
    part = create_part(organization: @personal)

    assert @user.destroy_account!

    assert_not User.exists?(@user.id)
    assert_not Organization.exists?(@personal.id)
    assert_not Part.exists?(part.id)
  end

  test "keeps shared organizations, whose history no longer names the user" do
    shared = create_organization(name: "Fablab")
    owner = create_user
    add_member(shared, owner, role: "owner")
    add_member(shared, @user)
    event = ActivityEvent.create!(organization: shared, user: @user, user_name: "Ada Lovelace", action: ActivityEvent::ACTIONS.first)
    loan = loan_for(shared, borrower: @user, borrower_name: "Ada Lovelace", borrower_contact: "ada@example.com")

    assert @user.destroy_account!

    assert Organization.exists?(shared.id)
    assert_nil event.reload.user_id
    assert_equal User::DELETED_USER_NAME, event.user_name
    loan.reload
    assert_nil loan.borrower_id
    assert_equal User::DELETED_USER_NAME, loan.borrower_name
    assert_nil loan.borrower_contact
  end

  test "an organization with only pending invitees or inactive members goes with its only owner" do
    org = create_organization(name: "Solo")
    add_member(org, @user, role: "owner")
    OrganizationMembership.create!(organization: org, user: create_user, role: "member", invitation_sent_at: Time.current)
    OrganizationMembership.create!(organization: org, user: create_user, role: "member", active: false)

    assert_empty @user.organizations_blocking_deletion
    assert @user.destroy_account!
    assert_not Organization.exists?(org.id)
  end

  test "refuses while the user is the only owner of an organization others use" do
    shared = create_organization(name: "Fablab")
    add_member(shared, @user, role: "owner")
    add_member(shared, create_user)

    assert_equal [ shared ], @user.organizations_blocking_deletion
    assert_not @user.destroy_account!
    assert User.exists?(@user.id)
    assert Organization.exists?(@personal.id)
  end

  test "another active owner lets the user go" do
    shared = create_organization(name: "Fablab")
    add_member(shared, @user, role: "owner")
    add_member(shared, create_user, role: "owner")

    assert_empty @user.organizations_blocking_deletion
    assert @user.destroy_account!
    assert Organization.exists?(shared.id)
  end
end
