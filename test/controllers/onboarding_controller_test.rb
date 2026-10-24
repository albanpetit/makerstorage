require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    sign_in @user
  end

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end

  test "a new organization's dashboard offers the templates" do
    get root_path

    assert inertia_props["getting_started"]["choose_template"]
  end

  test "an admin applies a template" do
    post onboarding_template_path, params: { template: "home_lab" }

    assert_redirected_to root_path
    assert_equal "home_lab", @org.reload.onboarding_template
    assert @org.categories.exists?
    get root_path
    assert_not inertia_props["getting_started"]["choose_template"]
    assert_not_includes inertia_props["getting_started"]["steps"].map { |step| step["key"] }, "members"
  end

  test "an unknown template is refused" do
    post onboarding_template_path, params: { template: "castle" }

    assert_redirected_to root_path
    assert_nil @org.reload.onboarding_template
  end

  test "members can't apply templates or put the first steps away" do
    org = create_organization
    org.organization_memberships.create!(user: create_user, role: "owner")
    org.organization_memberships.create!(user: @user, role: "member")
    post switch_organization_path(org)

    post onboarding_template_path, params: { template: "makerspace" }
    post dismiss_onboarding_path

    assert_not org.reload.categories.exists?
    assert_nil org.onboarding_dismissed_at
  end

  test "starting empty keeps the first steps without the template offer" do
    post skip_onboarding_path

    assert_equal Organization::NO_TEMPLATE, @org.reload.onboarding_template
    get root_path
    assert_not inertia_props["getting_started"]["choose_template"]
    assert inertia_props["getting_started"]["steps"].any?
  end

  test "dismissing puts the first steps away" do
    post dismiss_onboarding_path

    assert @org.reload.onboarding_dismissed_at
    get root_path
    assert_nil inertia_props["getting_started"]
  end

  test "opening the demo switches to it, and the owner deletes it in one click" do
    assert_difference -> { Organization.count }, 1 do
      post onboarding_demo_path
    end
    demo = @user.organizations.find_by!(demo: true)
    assert_redirected_to root_path

    get root_path
    assert inertia_props["auth"]["current_organization"]["demo"]
    assert_nil inertia_props["getting_started"]

    assert_no_difference -> { Organization.count } do
      post onboarding_demo_path
    end

    delete organization_path(demo)
    assert_not Organization.exists?(demo.id)
  end

  test "opening demos is rate limited per user" do
    OnboardingController::DEMO_RATE_LIMIT.times do
      post onboarding_demo_path
    end
    @user.organizations.where(demo: true).destroy_all

    assert_no_difference -> { Organization.count } do
      post onboarding_demo_path
    end
  end

  test "requires authentication" do
    sign_out @user
    post onboarding_demo_path
    assert_redirected_to new_user_session_path
  end
end
