require "test_helper"

# The storage quota is per organization, so a shared instance also caps how
# many organizations one account owns (MAX_ORGANIZATIONS_PER_USER).
class OrganizationLimitTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in @user
  end

  test "reads the limit from the environment" do
    { nil => nil, "" => nil, "0" => nil, "junk" => nil, "-3" => nil, "10" => 10 }.each do |value, expected|
      with_env("MAX_ORGANIZATIONS_PER_USER", value) do
        expected ? assert_equal(expected, Makerstorage.max_organizations_per_user_from_env) : assert_nil(Makerstorage.max_organizations_per_user_from_env, value.inspect)
      end
    end
  end

  test "an account can't create more organizations than the limit" do
    with_limit(2) do
      assert_difference -> { Organization.count }, 1 do
        post organizations_path, params: { organization: { name: "Second" } }
      end

      assert_no_difference -> { Organization.count } do
        post organizations_path, params: { organization: { name: "Third" } }
      end
      assert_match(/already own 2 organizations/, flash[:alert])
    end
  end

  test "organizations the user only belongs to don't count" do
    other = create_organization
    OrganizationMembership.create!(organization: other, user: @user, role: "admin")

    with_limit(2) do
      assert_difference -> { Organization.count }, 1 do
        post organizations_path, params: { organization: { name: "Second" } }
      end
    end
  end

  test "no limit by default" do
    assert_nil Rails.configuration.x.max_organizations_per_user
    3.times { |i| post organizations_path, params: { organization: { name: "Org #{i}" } } }
    assert_equal 4, @user.owned_organizations_count
  end

  test "creating organizations is rate limited" do
    OrganizationsController::CREATE_RATE_LIMIT.times { |i| post organizations_path, params: { organization: { name: "Org #{i}" } } }

    assert_no_difference -> { Organization.count } do
      post organizations_path, params: { organization: { name: "One too many" } }
    end
    assert_match(/Too many organizations/, flash[:alert])
  end

  test "a restore is refused at the limit" do
    with_limit(1) do
      error = assert_raises(OrganizationBackup::Error) do
        OrganizationBackup::Importer.new(Rails.root.join("Gemfile").to_s, user: @user).import!
      end
      assert_match(/already own 1 organizations/, error.message)
    end
  end

  private

  def with_limit(count)
    previous = Rails.configuration.x.max_organizations_per_user
    Rails.configuration.x.max_organizations_per_user = count
    yield
  ensure
    Rails.configuration.x.max_organizations_per_user = previous
  end

  def with_env(name, value)
    previous = ENV[name]
    ENV[name] = value
    yield
  ensure
    ENV[name] = previous
  end
end
