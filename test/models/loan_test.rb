require "test_helper"

class LoanTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
    @org.update!(timezone: "Etc/UTC")
    @shelf = create_storage_location(organization: @org, name: "Shelf")
    @bench = create_storage_location(organization: @org, name: "Bench")
    @iron = create_part(organization: @org, name: "Soldering iron")
    @scope = create_part(organization: @org, name: "Oscilloscope probe")
    stock(@iron, @shelf, 3)
    stock(@scope, @shelf, 2)
  end

  test "lending takes each line out of its zone and draws a reference" do
    loan = build_loan(lines: [ [ @iron, @shelf, 2 ], [ @scope, @shelf, 1 ] ])

    assert_difference -> { StockMovement.count } => 2, -> { Loan.count } => 1 do
      loan.lend!(user: @user)
    end

    assert_match(/\ALN-\d{8}-1\z/, loan.reference)
    assert_equal @user, loan.lent_by
    assert_equal 1, quantity(@iron, @shelf)
    assert_equal 1, quantity(@scope, @shelf)
    movement = StockMovement.where(part: @iron).order(:id).last
    assert_equal "out", movement.movement_type
    assert_equal(-2, movement.quantity_delta)
    assert_equal loan.reference, movement.reference
    assert_equal "Lent to Alice", movement.reason
    assert_equal "open", loan.status
  end

  test "lending more than the zone holds records nothing" do
    loan = build_loan(lines: [ [ @scope, @shelf, 1 ], [ @iron, @shelf, 4 ] ])

    assert_no_difference -> { StockMovement.count } do
      assert_no_difference -> { Loan.count } do
        assert_raises(ActiveRecord::RecordInvalid) { loan.lend!(user: @user) }
      end
    end
    assert_equal 3, quantity(@iron, @shelf)
    assert_equal 2, quantity(@scope, @shelf)
  end

  test "lending past the stock is allowed when the organization allows negative stock" do
    @org.update!(allow_negative_stock: true)
    build_loan(lines: [ [ @iron, @shelf, 5 ] ]).lend!(user: @user)
    assert_equal(-2, quantity(@iron, @shelf))
  end

  test "a loan needs a borrower name and at least one line" do
    loan = @org.loans.new(borrower_name: "")
    assert_not loan.valid?
    assert loan.errors.key?(:borrower_name)
    assert loan.errors[:base].any? { |message| message.include?("at least one item") }
  end

  test "the borrower must be an active member of the organization" do
    outsider = create_user
    loan = build_loan(lines: [ [ @iron, @shelf, 1 ] ])
    loan.borrower = outsider
    assert_not loan.valid?
    assert loan.errors.key?(:borrower)

    loan.borrower = @user
    assert loan.valid?
  end

  test "lines refuse a part or zone from another organization" do
    other = create_organization
    foreign_part = create_part(organization: other)
    foreign_zone = create_storage_location(organization: other)

    loan = build_loan(lines: [ [ foreign_part, @shelf, 1 ] ])
    assert_not loan.valid?
    assert loan.loan_lines.first.errors.key?(:part)

    loan = build_loan(lines: [ [ @iron, foreign_zone, 1 ] ])
    assert_not loan.valid?
    assert loan.loan_lines.first.errors.key?(:storage_location)
  end

  test "partial returns go back to the zone the items came from, then close the loan" do
    loan = build_loan(lines: [ [ @iron, @shelf, 2 ] ]).lend!(user: @user)
    line = loan.loan_lines.first

    loan.return_items!([ { line_id: line.id, quantity: 1 } ], user: @user)
    assert_equal 2, quantity(@iron, @shelf)
    assert_equal 1, line.reload.returned_quantity
    assert_not loan.reload.closed?

    loan.return_items!([ { line_id: line.id, quantity: 1, storage_location: @bench } ], user: @user)
    assert_equal 1, quantity(@iron, @bench)
    assert loan.reload.closed?
    assert_equal "returned", loan.status
    movement = StockMovement.order(:id).last
    assert_equal "in", movement.movement_type
    assert_equal "Returned by Alice", movement.reason
  end

  test "returning more than is still out changes nothing" do
    loan = build_loan(lines: [ [ @iron, @shelf, 2 ], [ @scope, @shelf, 1 ] ]).lend!(user: @user)
    iron, probe = loan.loan_lines.to_a

    assert_no_difference -> { StockMovement.count } do
      error = assert_raises(Loan::Error) do
        loan.return_items!([ { line_id: probe.id, quantity: 1 }, { line_id: iron.id, quantity: 3 } ], user: @user)
      end
      assert_match(/Only 2/, error.message)
    end
    assert_equal 0, probe.reload.returned_quantity
  end

  test "a return refuses a line of another loan and a zone of another organization" do
    loan = build_loan(lines: [ [ @iron, @shelf, 1 ] ]).lend!(user: @user)
    other_loan = build_loan(lines: [ [ @scope, @shelf, 1 ] ]).lend!(user: @user)
    foreign_zone = create_storage_location(organization: create_organization)

    assert_raises(Loan::Error) { loan.return_items!([ { line_id: other_loan.loan_lines.first.id, quantity: 1 } ], user: @user) }
    assert_raises(Loan::Error) do
      loan.return_items!([ { line_id: loan.loan_lines.first.id, quantity: 1, storage_location: foreign_zone } ], user: @user)
    end
  end

  test "return all puts everything still out back and closes the loan" do
    loan = build_loan(lines: [ [ @iron, @shelf, 2 ], [ @scope, @shelf, 2 ] ]).lend!(user: @user)
    loan.write_off!(line_id: loan.loan_lines.last.id, quantity: 1)

    loan.return_all!(user: @user)
    assert loan.reload.closed?
    assert_equal 3, quantity(@iron, @shelf)
    assert_equal 1, quantity(@scope, @shelf)
  end

  test "a return falls back to the part's first zone when the line's zone is gone" do
    loan = build_loan(lines: [ [ @iron, @shelf, 1 ] ]).lend!(user: @user)
    loan.loan_lines.first.update_column(:storage_location_id, nil)

    loan.return_all!(user: @user)
    assert_equal 3, quantity(@iron, @shelf)
  end

  test "writing off records the loss without touching stock" do
    loan = build_loan(lines: [ [ @iron, @shelf, 2 ] ]).lend!(user: @user)
    line = loan.loan_lines.first

    assert_no_difference -> { StockMovement.count } do
      loan.write_off!(line_id: line.id, quantity: 2)
    end
    assert_equal 2, line.reload.lost_quantity
    assert loan.reload.closed?
    assert_equal 1, quantity(@iron, @shelf)
  end

  test "a closed loan can't be settled again" do
    loan = build_loan(lines: [ [ @iron, @shelf, 1 ] ]).lend!(user: @user)
    loan.return_all!(user: @user)

    assert_no_difference -> { StockMovement.count } do
      assert_raises(Loan::Error) { loan.return_all!(user: @user) }
    end
  end

  test "overdue follows the due date and the organization's local date" do
    loan = build_loan(lines: [ [ @iron, @shelf, 1 ] ], due_on: Date.new(2026, 10, 19)).lend!(user: @user)

    assert_not loan.overdue?(Date.new(2026, 10, 19))
    assert loan.overdue?(Date.new(2026, 10, 21))
    assert_equal 2, loan.days_overdue(Date.new(2026, 10, 21))
    assert_equal "overdue", loan.status(Date.new(2026, 10, 21))
    assert_equal [ loan ], @org.loans.overdue_on(Date.new(2026, 10, 21)).to_a

    loan.return_all!(user: @user)
    assert_not loan.reload.overdue?(Date.new(2026, 10, 21))
    assert_empty @org.loans.overdue_on(Date.new(2026, 10, 21))
  end

  test "a loan without a due date is never overdue" do
    loan = build_loan(lines: [ [ @iron, @shelf, 1 ] ], due_on: nil).lend!(user: @user)
    assert_not loan.overdue?(Date.current + 1.year)
  end

  test "references count up within the day" do
    first = build_loan(lines: [ [ @iron, @shelf, 1 ] ]).lend!(user: @user)
    second = build_loan(lines: [ [ @iron, @shelf, 1 ] ]).lend!(user: @user)
    assert_equal first.reference.sub(/-1\z/, "-2"), second.reference
  end

  test "a part with loan history can't be deleted, a zone can and the line keeps its loan" do
    loan = build_loan(lines: [ [ @iron, @shelf, 1 ] ]).lend!(user: @user)
    loan.return_all!(user: @user)

    assert_not @iron.destroy
    assert @iron.errors.any?

    zone = create_storage_location(organization: @org)
    line = loan.loan_lines.first
    line.update_column(:storage_location_id, zone.id)
    assert zone.destroy
    assert_nil line.reload.storage_location_id
  end

  test "deleting the borrower's account keeps the loan and its name" do
    borrower = create_user(firstname: "Bob", lastname: "Martin")
    OrganizationMembership.create!(organization: @org, user: borrower, role: "member")
    loan = build_loan(lines: [ [ @iron, @shelf, 1 ] ])
    loan.borrower = borrower
    loan.lend!(user: borrower)

    Organization.where(id: borrower.organization_memberships.where(role: "owner").select(:organization_id)).find_each(&:destroy!)
    borrower.reload.destroy!
    loan.reload
    assert_nil loan.borrower_id
    assert_nil loan.lent_by_id
    assert_equal "Alice", loan.borrower_name
  end

  test "destroying the organization and resetting its data remove loans" do
    build_loan(lines: [ [ @iron, @shelf, 1 ] ]).lend!(user: @user)

    @org.reset_data!
    assert_equal 0, @org.loans.count
    assert_equal 0, LoanLine.joins(:loan).where(loans: { organization_id: @org.id }).count

    org = create_organization
    part = create_part(organization: org)
    zone = create_storage_location(organization: org)
    StockMovement.create!(organization: org, part: part, storage_location: zone, movement_type: "in", quantity_delta: 1)
    org.loans.new(borrower_name: "X").tap { |l| l.loan_lines.build(part: part, storage_location: zone, quantity: 1) }.lend!(user: @user)
    assert org.destroy
  end

  private

  def stock(part, zone, quantity)
    StockMovement.create!(organization: @org, part: part, storage_location: zone, movement_type: "in", quantity_delta: quantity)
  end

  def quantity(part, zone)
    PartStorage.find_by(part: part, storage_location: zone)&.quantity
  end

  def build_loan(lines:, due_on: Date.current + 14)
    loan = @org.loans.new(borrower_name: "Alice", due_on: due_on)
    lines.each { |part, zone, qty| loan.loan_lines.build(part: part, storage_location: zone, quantity: qty) }
    loan
  end
end
