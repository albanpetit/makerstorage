require "test_helper"

class OrganizationDemoTest < ActiveSupport::TestCase
  setup do
    @user = create_user
  end

  test "builds a demo the user owns, filled with stock, orders, projects and loans" do
    demo = OrganizationDemo.open_for!(@user)

    assert demo.demo?
    assert @user.owner_of?(demo)
    assert demo.onboarding_dismissed_at, "a demo shows no first steps"
    assert_equal "makerspace", demo.onboarding_template
    assert_equal OrganizationDemo::PARTS.size, demo.parts.count
    assert_equal %w[pending received shipped], demo.orders.pluck(:status).sort
    assert_equal 1, demo.orders.where(status: "pending").where(expected_delivery: ...Date.current).count
    assert_equal 2, demo.projects.count
    assert_equal 1, demo.loans.overdue_on(demo.local_date).count
    assert demo.parts.low_stock.exists?
    assert demo.parts.out_of_stock.exists?
    assert demo.stock_movements.where(created_at: ...30.days.ago).exists?
    assert demo.stock_movements.where(created_at: 30.days.ago..).where(movement_type: "out").exists?
  end

  test "keeps every stock row equal to its movements" do
    demo = OrganizationDemo.open_for!(@user)

    demo.parts.includes(:part_storages).each do |part|
      part.part_storages.each do |storage|
        assert_equal part.stock_movements.where(storage_location_id: storage.storage_location_id).sum(:quantity_delta), storage.quantity
        assert_operator storage.quantity, :>=, 0
      end
    end
  end

  test "opens the user's existing demo instead of building a second one" do
    demo = OrganizationDemo.open_for!(@user)

    assert_no_difference -> { Organization.count } do
      assert_equal demo, OrganizationDemo.open_for!(@user)
    end
  end

  test "writes nothing to the activity log" do
    Current.user = @user
    assert_no_difference -> { ActivityEvent.count } do
      OrganizationDemo.open_for!(@user)
    end
  ensure
    Current.user = nil
  end

  test "names follow the current locale" do
    demo = I18n.with_locale(:fr) { OrganizationDemo.open_for!(@user) }

    assert_equal "Atelier de démo", demo.name
    assert demo.projects.exists?(name: "Station météo")
  end

  test "can be deleted whole" do
    demo = OrganizationDemo.open_for!(@user)

    assert demo.destroy
    assert_not Organization.exists?(demo.id)
  end
end
