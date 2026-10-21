require "application_system_test_case"

# Lending a tool to a member from a part's detail, then getting it back.
class LoansTest < ApplicationSystemTestCase
  setup do
    @user = create_user(firstname: "Ada", lastname: "Lovelace")
    @org = @user.organizations.first
    @member = create_user(firstname: "Bob", lastname: "Martin")
    OrganizationMembership.create!(organization: @org, user: @member, role: "member")
    @shelf = create_storage_location(organization: @org, name: "Tool wall", code: "TW")
    @iron = create_part(organization: @org, name: "Soldering iron TS101", min_stock_threshold: 0)
    StockMovement.create!(organization: @org, part: @iron, storage_location: @shelf, movement_type: "in", quantity_delta: 2)

    visit new_user_session_path
    fill_in "Email address", with: @user.email
    fill_in "Password", with: "password123"
    click_on "Log in"
    assert_selector "h1", text: "Dashboard", wait: 20
  end

  test "lending to a member and returning" do
    visit loans_path(part_id: @iron.id)

    within("[role='dialog']") do
      assert_text "Soldering iron TS101"
      assert_text "Tool wall"
      find("#loan-borrower").click
    end
    find("[role='option']", text: "Bob Martin").click
    within("[role='dialog']") do
      fill_in "Notes", with: "For the Saturday workshop"
      screenshot("1-preter") if ENV["LOAN_SCREENSHOTS"]
      click_on "Lend"
    end

    assert_text "items taken out of stock"
    loan = @org.loans.sole
    assert_equal @member, loan.borrower
    assert_equal 1, @iron.reload.total_quantity
    screenshot("2-pret") if ENV["LOAN_SCREENSHOTS"]

    click_on "Return"
    within("[role='dialog']") { click_on "Return" }
    assert_text "Everything is back: loan closed."
    assert loan.reload.closed?
    assert_equal 2, @iron.reload.total_quantity
  end

  test "overdue loans are flagged in the list and the sidebar" do
    loan = @org.loans.new(borrower: @member, borrower_name: "Bob Martin", due_on: @org.local_date - 3)
    loan.loan_lines.build(part: @iron, storage_location: @shelf, quantity: 1)
    loan.lend!(user: @user)
    other = @org.loans.new(borrower_name: "Neighbour", due_on: @org.local_date + 5)
    other.loan_lines.build(part: @iron, storage_location: @shelf, quantity: 1)
    other.lend!(user: @user)

    visit loans_path
    assert_text "3 days late"
    assert_selector "[data-sidebar='menu-badge']", text: "1"
    screenshot("3-liste") if ENV["LOAN_SCREENSHOTS"]
  end

  private

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/loans-#{name}.png").to_s)
  end
end
