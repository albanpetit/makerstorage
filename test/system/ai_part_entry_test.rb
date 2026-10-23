require "application_system_test_case"

class AiPartEntrySystemTest < ApplicationSystemTestCase
  PNG = "\x89PNG\r\n\x1A\n".b + ("\x00".b * 32)

  setup do
    @user = create_user
    @org = @user.organizations.first
    @category = create_category(organization: @org, name: "Resistors")

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "an admin saves a Claude key, and the add-part dialog fills in from a photo" do
    visit settings_path
    click_on "Integrations"
    fill_in "Anthropic API key", with: "sk-ant-test"
    within(:xpath, "//div[@data-slot='card'][.//*[text()='Claude (AI-assisted entry)']]") { click_on "Save" }
    assert_text "A key is configured"
    assert @org.reload.ai_entry_configured?

    extraction = Object.new
    category_id = @category.id
    extraction.define_singleton_method(:extract) do |*, **|
      PartExtraction::TEXT_FIELDS.index_with { nil }.merge(
        "name" => "Resistor 10k 1% 0603", "mpn" => "RC0603FR-0710KL", "manufacturer" => "YAGEO", "value" => "10k",
        "category_id" => category_id, "footprint_id" => nil, "parameters" => {}, "quantity" => 100,
        "rohs_compliant" => true, "notes" => "Check the power rating on the datasheet.", "existing_part" => nil
      )
    end

    photo = Tempfile.new([ "label", ".png" ])
    photo.binmode
    photo.write(PNG)
    photo.close

    stub_singleton(PartExtraction, :new, ->(*) { extraction }) do
      visit parts_path(new: 1)
      assert_text "Fill in with AI"
      find("input[aria-label='Photos or datasheet']").attach_file(photo.path)
      click_on "Read"
      assert_text "The form was filled in from your files"
      assert_text "Check the power rating on the datasheet."
      assert_field "e.g. Resistor 10k 1% 0603", with: "Resistor 10k 1% 0603"
      assert_text "Photo will be the part image"

      within("[role='dialog']") { click_on "Add part" }
      assert_text "Part created successfully."
    end

    part = @org.parts.find_by!(mpn: "RC0603FR-0710KL")
    assert_equal "Resistor 10k 1% 0603", part.name
    assert_equal @category, part.category
    assert part.images.attached?
  end
end
