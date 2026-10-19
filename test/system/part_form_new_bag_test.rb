require "application_system_test_case"

# Box & bag numbering: the add-part form can open a new bag in a box when no
# free bag suits, without a detour through Storage zones.
class PartFormNewBagTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @org.update!(ipn_generation_mode: "box_bag")
    @box = create_storage_location(organization: @org, name: "Box A", location_type: "box", code: "A")
    @box.add_bags!(1)
    create_part(organization: @org, name: "Holder") # takes A-1
    create_category(organization: @org, name: "Capacitors")

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "adding a part in a new bag" do
    visit parts_path(new: 1)

    within("[role='dialog']") do
      find("input[placeholder='e.g. Resistor 10k 1% 0603']").fill_in(with: "Cap 100n")
      find("button[role='combobox']", text: "Select a category").click
    end
    find("[role='option']", text: "Capacitors").click

    within("[role='dialog']") { find("button[role='combobox']", text: "No free bag").click }
    find("[role='option']", text: "A-2").click

    within("[role='dialog']") do
      assert_text "This bag is added to its box when the part is saved"
      click_on "Add part"
    end

    assert_text "Part created successfully."
    part = @org.parts.find_by!(name: "Cap 100n")
    assert_equal "A-2", part.ipn
    assert_equal @box, part.bag.parent
  end
end
