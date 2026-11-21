require "test_helper"

class PartCsvImportJobTest < ActiveJob::TestCase
  setup do
    @user = create_user
    @org = @user.organizations.first
  end

  def import_of(content)
    @org.part_imports.create!(user: @user, filename: "parts.csv", total_rows: 1).tap do |part_import|
      FileUtils.mkdir_p(PartImport::DIRECTORY)
      File.binwrite(part_import.file_path, content)
    end
  end

  test "imports the file, saves the counts and signs the event with the user" do
    part_import = import_of("Name,Category,MPN\nResistor,Resistors,R-1\n,Resistors,R-2\n")

    PartCsvImportJob.perform_now(part_import)

    part_import.reload
    assert_equal [ "done", 2, 1, 0, 1 ],
      [ part_import.status, part_import.processed_rows, part_import.created_count, part_import.updated_count, part_import.skipped_count ]
    event = @org.activity_events.newest_first.first
    assert_equal [ "import", @user.id, "parts.csv" ], [ event.action, event.user_id, event.details["file"] ]
    assert_not File.exist?(part_import.file_path)
    assert_nil Current.user
  end

  test "a user who can no longer write when the job starts gets a failed import, and nothing is imported" do
    part_import = import_of("Name,Category\nResistor,Resistors\n")
    OrganizationMembership.create!(organization: @org, user: create_user, role: "owner")
    @org.organization_memberships.find_by!(user: @user).update!(role: "viewer")

    PartCsvImportJob.perform_now(part_import)

    assert_equal [ "failed", "no_longer_allowed" ], part_import.reload.values_at(:status, :error)
    assert_equal 0, @org.parts.count
    assert_not File.exist?(part_import.file_path)
  end

  test "imports run one at a time on the server" do
    assert_equal 1, PartCsvImportJob.concurrency_limit
    assert_equal "part_csv_import", PartCsvImportJob.new(import_of("x")).concurrency_key.split("/").last
    assert PartCsvImportJob.concurrency_duration >= 1.hour
  end

  test "an unreadable file fails the import with a reason" do
    part_import = import_of("Name,Category\n\"broken,quote\n")

    PartCsvImportJob.perform_now(part_import)

    assert_equal [ "failed", "unreadable" ], part_import.reload.values_at(:status, :error)
    assert_match(/CSV/, part_import.message)
    assert_not File.exist?(part_import.file_path)
  end

  test "a file lost before the job ran fails the import" do
    part_import = @org.part_imports.create!(user: @user, filename: "parts.csv", total_rows: 1)

    PartCsvImportJob.perform_now(part_import)

    assert_equal [ "failed", "file_missing" ], part_import.reload.values_at(:status, :error)
  end

  test "an unexpected error fails the import and is raised for the queue's log" do
    part_import = import_of("Name,Category\nA,B\n")

    stub_singleton(BomParser, :each_row, ->(*) { raise "boom" }) do
      assert_raises(RuntimeError) { PartCsvImportJob.perform_now(part_import) }
    end

    assert_equal [ "failed", "unexpected" ], part_import.reload.values_at(:status, :error)
  end

  test "old imports and their files are swept" do
    old = import_of("Name,Category\nA,B\n")
    old.update_column(:created_at, (PartImport::KEPT_FOR + 1.day).ago)
    recent = import_of("Name,Category\nA,B\n")

    PartImport.sweep(@org)

    assert_not PartImport.exists?(old.id)
    assert_not File.exist?(old.file_path)
    assert PartImport.exists?(recent.id)
    FileUtils.rm_f(recent.file_path)
  end
end
