require "test_helper"

class PartSupplierTest < ActiveSupport::TestCase
  setup do
    @org = create_organization
    @part = create_part(organization: @org)
  end

  test "a preferred supplier price sets the part's unit_price" do
    supplier = create_supplier(organization: @org)
    PartSupplier.create!(part: @part, supplier: supplier, unit_price: 1.5, is_preferred: true)

    assert_equal 1.5, @part.reload.unit_price.to_f
  end

  test "repricing the preferred supplier updates the part's unit_price" do
    supplier = create_supplier(organization: @org)
    ps = PartSupplier.create!(part: @part, supplier: supplier, unit_price: 1.5, is_preferred: true)

    ps.update!(unit_price: 2.25)

    assert_equal 2.25, @part.reload.unit_price.to_f
  end

  test "a non-preferred supplier price does not change the part's unit_price" do
    @part.update!(unit_price: 9)
    supplier = create_supplier(organization: @org)
    PartSupplier.create!(part: @part, supplier: supplier, unit_price: 1.5, is_preferred: false)

    assert_equal 9, @part.reload.unit_price.to_f
  end

  test "switching the preferred supplier re-syncs the part's unit_price" do
    first = PartSupplier.create!(part: @part, supplier: create_supplier(organization: @org), unit_price: 1, is_preferred: true)
    second = PartSupplier.create!(part: @part, supplier: create_supplier(organization: @org), unit_price: 2, is_preferred: false)
    assert_equal 1, @part.reload.unit_price.to_f

    second.update!(is_preferred: true)

    assert_equal 2, @part.reload.unit_price.to_f
    assert_not first.reload.is_preferred?
  end

  test "a preferred supplier without a price leaves a manual unit_price untouched" do
    @part.update!(unit_price: 3.5)
    supplier = create_supplier(organization: @org)
    PartSupplier.create!(part: @part, supplier: supplier, unit_price: nil, is_preferred: true)

    assert_equal 3.5, @part.reload.unit_price.to_f
  end

  test "removing the preferred supplier keeps the last synced price" do
    supplier = create_supplier(organization: @org)
    ps = PartSupplier.create!(part: @part, supplier: supplier, unit_price: 1.5, is_preferred: true)
    assert_equal 1.5, @part.reload.unit_price.to_f

    ps.destroy

    assert_equal 1.5, @part.reload.unit_price.to_f
  end
end
