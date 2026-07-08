require "test_helper"

class UserTest < ActiveSupport::TestCase
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
