require "test_helper"

class ProjectGithubSyncTest < ActiveSupport::TestCase
  SHA1 = "a" * 40
  SHA2 = "b" * 40
  SHA3 = "c" * 40

  setup do
    @org = create_organization
    category = create_category(organization: @org)
    @cap = create_part(organization: @org, category: category, name: "MLCC 100nF", sku: "C14663")
    @project = create_project(organization: @org, github_repository: "maker/rover", github_path: "hw")
  end

  test "fetches the KiCad files under the folder into one ZIP and fills the BOM" do
    fake = FakeGithub.new(commits: { nil => SHA1 }, archives: { SHA1 => repo_files })

    result = with_fake_github(fake) { ProjectGithubSync.call(@project) }

    assert_equal [ :updated, SHA1, 4, :replaced, 3 ], [ result.status, result.sha, result.file_count, result.bom, result.line_count ]
    @project.reload
    assert_equal SHA1, @project.github_synced_sha
    assert @project.github_synced_at.present?
    assert_equal 3, @project.project_lines.count
    assert_equal @cap, @project.project_lines.find_by(value: "100nF").part

    file = @project.kicad_files.sole
    assert_equal [ "rover-aaaaaaa.zip", Project::ZIP_TYPE, SHA1 ], [ file.filename.to_s, file.content_type, file.blob.metadata["github_sha"] ]
    names = file.blob.open { |zip| Zip::File.open(zip.path) { |z| z.entries.map(&:name).sort } }
    assert_equal %w[board.kicad_pcb board.kicad_pro board.kicad_sch sub/sensor.kicad_sch], names
  end

  test "reads the whole repository without a folder, and passes the organization's token" do
    @project.update!(github_path: nil, github_ref: "v2")
    @org.update_columns(github_token: "ghp_secret")
    fake = FakeGithub.new(commits: { "v2" => SHA1 }, archives: { SHA1 => repo_files })

    result = with_fake_github(fake) { ProjectGithubSync.call(@project) }

    assert_equal 5, result.file_count # the firmware folder's .kicad_sym counts too
    assert_equal [ "ghp_secret" ], fake.tokens
    assert_equal [ :commit_sha, "maker/rover", "v2" ], fake.calls.first
  end

  test "downloads nothing when the commit is the one already fetched" do
    fake = FakeGithub.new(commits: { nil => SHA1 }, archives: { SHA1 => repo_files })
    with_fake_github(fake) { ProjectGithubSync.call(@project) }

    result = with_fake_github(fake) { ProjectGithubSync.call(@project.reload) }

    assert_equal :up_to_date, result.status
    assert_equal 1, fake.calls.count { |call| call.first == :download_archive }
  end

  test "a new commit replaces the fetched ZIP, keeps hand-added files, and leaves an unchanged BOM confirmed" do
    fake = FakeGithub.new(commits: { nil => SHA1 }, archives: { SHA1 => repo_files, SHA2 => repo_files.merge("README.md" => "v2") })
    with_fake_github(fake) { ProjectGithubSync.call(@project) }
    @project.reload
    @project.kicad_files.attach(io: StringIO.new("(kicad_wks)"), filename: "frame.kicad_wks", content_type: Project::KICAD_FILE_TYPE)
    @project.update!(status: "confirmed", reserved_at: Time.current)

    fake = FakeGithub.new(commits: { nil => SHA2 }, archives: { SHA2 => repo_files.merge("README.md" => "v2") })
    result = with_fake_github(fake) { ProjectGithubSync.call(@project.reload) }

    assert_equal [ :updated, :unchanged ], [ result.status, result.bom ]
    @project.reload
    assert_equal %w[frame.kicad_wks rover-bbbbbbb.zip], @project.kicad_files.map { |f| f.filename.to_s }.sort
    assert_equal [ "confirmed", true ], [ @project.status, @project.reserved_at.present? ]
  end

  test "a changed schematic replaces the BOM, keeping hand-picked parts, and sends the project back to draft" do
    fake = FakeGithub.new(commits: { nil => SHA1 }, archives: { SHA1 => repo_files })
    with_fake_github(fake) { ProjectGithubSync.call(@project) }
    resistor = create_part(organization: @org, name: "Resistor 10k")
    @project.reload.project_lines.find_by(value: "10k").update!(part: resistor, match_type: "manual")
    @project.update!(status: "confirmed")

    changed = repo_files.except("hw/sub/sensor.kicad_sch")
    fake = FakeGithub.new(commits: { nil => SHA3 }, archives: { SHA3 => changed })
    result = with_fake_github(fake) { ProjectGithubSync.call(@project.reload) }

    assert_equal :replaced, result.bom
    @project.reload
    assert_equal "draft", @project.status
    assert_equal [ resistor, "manual", 2 ], @project.project_lines.find_by(value: "10k").then { |l| [ l.part, l.match_type, l.quantity ] }
  end

  test "reports a folder without KiCad files and GitHub errors, keeping the project as it was" do
    fake = FakeGithub.new(commits: { nil => SHA1 }, archives: { SHA1 => { "README.md" => "hi" } })
    error = assert_raises(ProjectGithubSync::Error) { with_fake_github(fake) { ProjectGithubSync.call(@project) } }
    assert_equal "No KiCad files in maker/rover/hw.", error.message

    fake = FakeGithub.new(error: "Could not find maker/rover on GitHub.")
    error = assert_raises(ProjectGithubSync::Error) { with_fake_github(fake) { ProjectGithubSync.call(@project) } }
    assert_equal "Could not find maker/rover on GitHub.", error.message

    @project.reload
    assert_nil @project.github_synced_sha
    assert_empty @project.kicad_files
  end

  test "skips autosaves, lock files and backup folders" do
    files = repo_files.merge(
      "hw/_autosave-board.kicad_sch" => "junk", "hw/~board.kicad_sch.lck" => "junk",
      "hw/board-backups/old.kicad_sch" => "junk", "hw/.history/board.kicad_sch" => "junk"
    )
    fake = FakeGithub.new(commits: { nil => SHA1 }, archives: { SHA1 => files })

    assert_equal 4, with_fake_github(fake) { ProjectGithubSync.call(@project) }.file_count
  end

  private

  def repo_files
    {
      "README.md" => "# Rover",
      "firmware/main.c" => "int main() {}",
      "firmware/lib/logo.kicad_sym" => "(kicad_symbol_lib)",
      "hw/board.kicad_pro" => fixture("board/board.kicad_pro"),
      "hw/board.kicad_sch" => fixture("board/board.kicad_sch"),
      "hw/sub/sensor.kicad_sch" => fixture("board/sensor.kicad_sch"),
      "hw/board.kicad_pcb" => "(kicad_pcb)",
      "hw/gerbers.zip" => "PK"
    }
  end

  def fixture(name)
    file_fixture("kicad/#{name}").binread
  end
end
