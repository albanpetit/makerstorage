require "test_helper"

class LocaleTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in @user
  end

  test "English by default" do
    get profile_path
    assert_equal "en", inertia_props["locale"]
  end

  test "follows the browser's preferred language when the user picked none" do
    get profile_path, headers: { "Accept-Language" => "fr-CA,fr;q=0.9,en;q=0.8" }
    assert_equal "fr", inertia_props["locale"]

    get profile_path, headers: { "Accept-Language" => "de-DE,en;q=0.5,fr;q=0.7" }
    assert_equal "fr", inertia_props["locale"]

    get profile_path, headers: { "Accept-Language" => "de-DE,es" }
    assert_equal "en", inertia_props["locale"]
  end

  test "the user's choice wins over the browser" do
    @user.update!(locale: "en")
    get profile_path, headers: { "Accept-Language" => "fr" }
    assert_equal "en", inertia_props["locale"]
  end

  test "picking a language saves it and answers in that language" do
    patch profile_locale_path, params: { locale: "fr" }

    assert_redirected_to profile_path
    assert_equal "fr", @user.reload.locale
    assert_equal "Langue mise à jour.", flash[:notice]

    follow_redirect!
    assert_equal "fr", inertia_props["locale"]
    assert_equal "fr", inertia_props["user"]["locale"]
  end

  test "picking the browser's language clears the choice" do
    @user.update!(locale: "fr")

    patch profile_locale_path, params: { locale: "" }, headers: { "Accept-Language" => "en-GB" }

    assert_nil @user.reload.locale
    assert_equal "Language updated.", flash[:notice]
  end

  test "an unknown language falls back to the browser's" do
    @user.update!(locale: "fr")
    patch profile_locale_path, params: { locale: "xx" }
    assert_nil @user.reload.locale
  end

  test "flash messages follow the locale" do
    @user.update!(locale: "fr")

    post tags_path, params: { tag: { name: "" } }
    assert_equal "Impossible de créer le tag.", flash[:alert]
  end

  test "a failed sign-in answers in the browser's language" do
    delete destroy_user_session_path
    post user_session_path, params: { user: { email: @user.email, password: "wrong" } }, headers: { "Accept-Language" => "fr" }
    assert_match(/mot de passe incorrect|invalide/i, flash[:alert].to_s)
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end
