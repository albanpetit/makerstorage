require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "signup creates a personal organization owned by the user" do
    user = create_user(firstname: "Grace", lastname: "Hopper")

    org = user.organizations.first
    assert_equal "Grace's Organization", org.name
    assert org.personal?
    assert user.owner_of?(org)
  end

  test "personal_organization resolves by the personal flag even after a rename" do
    user = create_user(firstname: "Grace", lastname: "Hopper")
    org = user.organizations.first
    org.update!(name: "Renamed Space")

    assert_equal org, user.personal_organization
  end

  test "writer_of? is true for owner, admin, and member roles" do
    %w[owner admin member].each do |role|
      user = create_user(email: "#{role}_#{SecureRandom.hex(4)}@example.com")
      org = create_organization
      OrganizationMembership.create!(organization: org, user: user, role: role)
      assert user.writer_of?(org), "expected #{role} to be a writer"
    end
  end

  test "writer_of? is false for viewers" do
    user = create_user
    org = create_organization
    OrganizationMembership.create!(organization: org, user: user, role: "viewer")
    assert_not user.writer_of?(org)
  end

  test "writer_of? is false for a non-member" do
    user = create_user
    org = create_organization
    assert_not user.writer_of?(org)
  end
end
