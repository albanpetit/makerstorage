require "test_helper"

class PartCsvImportTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
  end

  def csv_file(content)
    Tempfile.new([ "parts", ".csv" ]).tap do |file|
      file.write(content)
      file.flush
    end
  end

  test "counts the rows without the header" do
    assert_equal 2, PartCsvImport.count_rows(csv_file("Name,Category\nA,B\nC,D\n").path)
  end

  test "reports progress every few rows" do
    file = csv_file("Name,Category,MPN\n" + (1..5).map { |i| "Part #{i},Resistors,P-#{i}\n" }.join)
    seen = []

    result = stub_const(PartCsvImport, :PROGRESS_EVERY, 2) do
      PartCsvImport.new(@org, @user).call(file.path) { |processed, counts| seen << [ processed, counts.created ] }
    end

    assert_equal [ [ 2, 2 ], [ 4, 4 ] ], seen
    assert_equal 5, result.created
  end

  test "records no activity event per part" do
    file = csv_file("Name,Category\nA,B\n")

    assert_no_difference -> { @org.activity_events.count } do
      PartCsvImport.new(@org, @user).call(file.path)
    end
  end
end
