require "test_helper"

class LoansControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(firstname: "Ada", lastname: "Lovelace")
    @org = @user.organizations.first
    @org.update!(timezone: "Etc/UTC", default_loan_days: 7)
    @shelf = create_storage_location(organization: @org, name: "Shelf")
    @iron = create_part(organization: @org, name: "Soldering iron")
    StockMovement.create!(organization: @org, part: @iron, storage_location: @shelf, movement_type: "in", quantity_delta: 3)
    @member = create_user(firstname: "Bob", lastname: "Martin")
    OrganizationMembership.create!(organization: @org, user: @member, role: "member")
  end

  test "redirects a signed-out visitor to login" do
    get loans_path
    assert_redirected_to new_user_session_path
  end

  test "index lists open loans with counts, members, lendable parts and the default due date" do
    loan = lend(borrower_name: "Alice")
    sign_in @user

    get loans_path(part_id: @iron.id)
    assert_response :success
    props = inertia_props
    assert_equal "open", props["filter"]
    assert_equal [ loan.id ], props["loans"].map { |l| l["id"] }
    assert_equal({ "open" => 1, "overdue" => 0, "returned" => 0 }, props["counts"])
    assert_equal [ "Ada Lovelace", "Bob Martin" ], props["members"].map { |m| m["name"] }
    assert_equal [ @iron.id ], props["parts"].map { |p| p["id"] }
    assert_equal [ { "id" => @shelf.id, "name" => "Shelf", "quantity" => 2 } ], props["parts"].first["locations"]
    assert_equal (@org.local_date + 7).iso8601, props["default_due_on"]
    assert_equal @iron.id, props["prefill_part_id"]
  end

  test "index filters overdue, returned and the user's own loans" do
    overdue = lend(borrower_name: "Alice", due_on: @org.local_date - 2)
    returned = lend(borrower_name: "Carol")
    returned.return_all!(user: @user)
    mine = lend(borrower: @member)
    sign_in @member

    get loans_path(filter: "overdue")
    assert_equal [ overdue.id ], inertia_props["loans"].map { |l| l["id"] }
    assert_equal 2, inertia_props["loans"].first["days_overdue"]

    get loans_path(filter: "returned")
    assert_equal [ returned.id ], inertia_props["loans"].map { |l| l["id"] }

    get loans_path(filter: "all")
    assert_equal [ mine.id, returned.id, overdue.id ].sort, inertia_props["loans"].map { |l| l["id"] }.sort

    get loans_path(mine: "1")
    assert_equal [ mine.id ], inertia_props["loans"].map { |l| l["id"] }
    assert inertia_props["loans"].first["mine"]
  end

  test "the sidebar badge counts overdue loans" do
    lend(borrower_name: "Alice", due_on: @org.local_date - 1)
    lend(borrower_name: "Bob", due_on: @org.local_date)
    sign_in @user

    get loans_path
    assert_equal 1, inertia_props.dig("auth", "overdue_loans_count")
  end

  test "create lends to a member, takes the items out of stock and opens the loan" do
    sign_in @user

    assert_difference -> { Loan.count } => 1, -> { StockMovement.count } => 1 do
      post loans_path, params: { loan: {
        borrower_id: @member.id, due_on: "2026-11-01", notes: "For the workshop",
        lines: [ { part_id: @iron.id, storage_location_id: @shelf.id, quantity: 2 } ]
      } }
    end

    loan = Loan.last
    assert_redirected_to loan_path(loan)
    assert_equal @member, loan.borrower
    assert_equal "Bob Martin", loan.borrower_name
    assert_equal @member.email, loan.borrower_contact
    assert_equal @user, loan.lent_by
    assert_equal Date.new(2026, 11, 1), loan.due_on
    assert_equal 1, PartStorage.find_by(part: @iron, storage_location: @shelf).quantity
  end

  test "create lends to someone outside the organization by name" do
    sign_in @user
    post loans_path, params: { loan: {
      borrower_name: "Neighbour", borrower_contact: "06 12 34 56 78",
      lines: [ { part_id: @iron.id, storage_location_id: @shelf.id, quantity: 1 } ]
    } }

    loan = Loan.last
    assert_nil loan.borrower
    assert_equal "Neighbour", loan.borrower_name
    assert_nil loan.due_on
  end

  test "create refuses more than the stock and leaves nothing behind" do
    sign_in @user

    assert_no_difference -> { Loan.count } do
      assert_no_difference -> { StockMovement.count } do
        post loans_path, params: { loan: {
          borrower_name: "Alice", lines: [ { part_id: @iron.id, storage_location_id: @shelf.id, quantity: 4 } ]
        } }
      end
    end
    assert_match(/not enough stock/, flash[:alert])
    assert_equal 3, PartStorage.find_by(part: @iron, storage_location: @shelf).quantity
  end

  test "create refuses a borrower, part or zone outside the organization" do
    other = create_organization
    outsider = create_user
    foreign_part = create_part(organization: other)
    foreign_zone = create_storage_location(organization: other)
    sign_in @user

    assert_no_difference -> { Loan.count } do
      post loans_path, params: { loan: { borrower_id: outsider.id, lines: [ { part_id: @iron.id, storage_location_id: @shelf.id, quantity: 1 } ] } }
      post loans_path, params: { loan: { borrower_name: "A", lines: [ { part_id: foreign_part.id, storage_location_id: @shelf.id, quantity: 1 } ] } }
      post loans_path, params: { loan: { borrower_name: "A", lines: [ { part_id: @iron.id, storage_location_id: foreign_zone.id, quantity: 1 } ] } }
      post loans_path, params: { loan: { borrower_name: "A" } }
    end
    assert flash[:alert].present?
  end

  test "show renders the loan and its lines" do
    loan = lend(borrower_name: "Alice")
    sign_in @user

    get loan_path(loan)
    assert_response :success
    props = inertia_props
    assert_equal loan.reference, props.dig("loan", "reference")
    assert_equal "open", props.dig("loan", "status")
    assert_equal 1, props.dig("loan", "lines", 0, "outstanding")
    assert_equal "Shelf", props.dig("loan", "lines", 0, "storage_location", "name")
  end

  test "show switches to the organization a digest link names" do
    other = create_organization
    OrganizationMembership.create!(organization: other, user: @user, role: "owner")
    part = create_part(organization: other)
    zone = create_storage_location(organization: other)
    StockMovement.create!(organization: other, part: part, storage_location: zone, movement_type: "in", quantity_delta: 1)
    loan = other.loans.new(borrower_name: "Alice").tap { |l| l.loan_lines.build(part: part, storage_location: zone, quantity: 1) }
    loan.lend!(user: @user)
    sign_in @user

    get loan_path(loan, organization_id: other.id)
    assert_response :success
  end

  test "another organization's loan is not found" do
    other = create_organization
    part = create_part(organization: other)
    zone = create_storage_location(organization: other)
    StockMovement.create!(organization: other, part: part, storage_location: zone, movement_type: "in", quantity_delta: 1)
    loan = other.loans.new(borrower_name: "Alice").tap { |l| l.loan_lines.build(part: part, storage_location: zone, quantity: 1) }
    loan.lend!(user: @user)
    sign_in @user

    get loan_path(loan)
    assert_response :not_found

    sign_in @user
    assert_no_difference -> { StockMovement.count } do
      post return_all_loan_path(loan)
    end
    assert_response :not_found
  end

  test "return_items puts a quantity back into the chosen zone" do
    loan = lend(borrower_name: "Alice", quantity: 2)
    bench = create_storage_location(organization: @org, name: "Bench")
    sign_in @user

    post return_items_loan_path(loan), params: { lines: [ { line_id: loan.loan_lines.first.id, quantity: 1, storage_location_id: bench.id } ] }
    assert_redirected_to loan_path(loan)
    assert_equal 1, PartStorage.find_by(part: @iron, storage_location: bench).quantity
    assert_not loan.reload.closed?

    post return_items_loan_path(loan), params: { lines: [ { line_id: loan.loan_lines.first.id, quantity: 5 } ] }
    assert_match(/Only 1/, flash[:alert])
  end

  test "return_all closes the loan, write_off records a loss" do
    loan = lend(borrower_name: "Alice", quantity: 2)
    sign_in @user

    post write_off_loan_path(loan), params: { line_id: loan.loan_lines.first.id, quantity: 1 }
    assert_equal 1, loan.loan_lines.first.reload.lost_quantity

    post return_all_loan_path(loan)
    assert loan.reload.closed?
    assert_equal 2, PartStorage.find_by(part: @iron, storage_location: @shelf).quantity

    post return_all_loan_path(loan)
    assert_match(/already closed/, flash[:alert])
  end

  test "update extends the due date" do
    loan = lend(borrower_name: "Alice")
    sign_in @user

    patch loan_path(loan), params: { loan: { due_on: "2027-01-15", borrower_contact: "alice@example.com", notes: "Extended" } }
    assert_redirected_to loan_path(loan)
    loan.reload
    assert_equal Date.new(2027, 1, 15), loan.due_on
    assert_equal "alice@example.com", loan.borrower_contact
    assert_equal "Extended", loan.notes
  end

  test "a viewer sees loans but can't lend, return or edit" do
    loan = lend(borrower_name: "Alice")
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer
    post switch_organization_path(@org)

    get loans_path
    assert_response :success
    get loan_path(loan)
    assert_response :success

    assert_no_difference -> { Loan.count } do
      post loans_path, params: { loan: { borrower_name: "A", lines: [ { part_id: @iron.id, storage_location_id: @shelf.id, quantity: 1 } ] } }
    end
    post return_all_loan_path(loan)
    patch loan_path(loan), params: { loan: { due_on: "2030-01-01" } }
    assert_not loan.reload.closed?
    assert_not_equal Date.new(2030, 1, 1), loan.due_on
  end

  test "the part detail lists the open loans holding it" do
    loan = lend(borrower_name: "Alice", due_on: @org.local_date - 1)
    sign_in @user

    get part_path(@iron, format: :json)
    loans = JSON.parse(response.body)["loans"]
    assert_equal [ { "loan_id" => loan.id, "reference" => loan.reference, "borrower_name" => "Alice",
                     "quantity" => 1, "due_on" => loan.due_on.iso8601, "overdue" => true } ], loans
  end

  private

  def lend(borrower_name: nil, borrower: nil, due_on: nil, quantity: 1)
    loan = @org.loans.new(borrower_name: borrower_name || borrower.display_name, borrower: borrower, due_on: due_on)
    loan.loan_lines.build(part: @iron, storage_location: @shelf, quantity: quantity)
    loan.lend!(user: @user)
  end

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end
