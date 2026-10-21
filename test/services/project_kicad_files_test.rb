require "test_helper"

class ProjectKicadFilesTest < ActiveSupport::TestCase
  test "reads the schematics out of a zipped project, skipping autosaves and backups" do
    zip = zip_file(
      "board/board.kicad_sch" => fixture("board/board.kicad_sch"),
      "board/sensor.kicad_sch" => fixture("board/sensor.kicad_sch"),
      "board/board.kicad_pro" => fixture("board/board.kicad_pro"),
      "board/_autosave-board.kicad_sch" => "not even a schematic",
      "board/board-backups/old.kicad_sch" => "not even a schematic"
    )

    lines = ProjectKicadFiles.bom_lines([ [ "board.zip", zip.path ] ])

    assert_equal [ 1, 4, 1 ], lines.map { |line| line[:quantity] }
  end

  test "reads loose schematics and ignores the other KiCad files" do
    lines = ProjectKicadFiles.bom_lines([
      [ "board.kicad_pro", fixture_path("board/board.kicad_pro") ],
      [ "board.kicad_sch", fixture_path("board/board.kicad_sch") ]
    ])

    assert_equal [ "100nF", "10k", "LM358" ], lines.map { |line| line[:value] }
    assert_empty ProjectKicadFiles.bom_lines([ [ "board.kicad_pro", fixture_path("board/board.kicad_pro") ] ])
  end

  test "reports an unreadable archive, an old schematic and an oversized one" do
    junk = Tempfile.new([ "junk", ".zip" ]).tap { |f| f.write("not a zip") && f.flush }
    error = assert_raises(ProjectKicadFiles::Unreadable) { ProjectKicadFiles.bom_lines([ [ "board.zip", junk.path ] ]) }
    assert_match(/Could not open board.zip/, error.message)

    old = zip_file("v5/board.kicad_sch" => "EESchema Schematic File Version 4\n")
    error = assert_raises(ProjectKicadFiles::Unreadable) { ProjectKicadFiles.bom_lines([ [ "v5.zip", old.path ] ]) }
    assert_match(/board.kicad_sch isn't a KiCad schematic/, error.message)

    huge = zip_file("board.kicad_sch" => "(kicad_sch #{' ' * BomParser::MAX_FILE_SIZE})")
    error = assert_raises(ProjectKicadFiles::Unreadable) { ProjectKicadFiles.bom_lines([ [ "huge.zip", huge.path ] ]) }
    assert_match(/too large/, error.message)
  end

  test "names a project after its .kicad_pro, else its schematic or archive" do
    assert_equal "board", ProjectKicadFiles.project_name(%w[board.kicad_pcb board.kicad_pro sensor.kicad_sch])
    assert_equal "sensor", ProjectKicadFiles.project_name(%w[board.kicad_pcb sensor.kicad_sch])
    assert_equal "rover", ProjectKicadFiles.project_name(%w[rover.zip])
  end

  test "upload_error refuses other files, too many files and oversized ones" do
    assert_nil ProjectKicadFiles.upload_error([ upload("board.kicad_sch"), upload("board.zip"), upload("fp-lib-table") ])
    assert_match(/notes.txt isn't a KiCad file/, ProjectKicadFiles.upload_error([ upload("board.kicad_sch"), upload("notes.txt") ]))
    assert_match(/at most #{Project::MAX_KICAD_FILES}/, ProjectKicadFiles.upload_error([ upload("a.kicad_sch") ], existing: Project::MAX_KICAD_FILES))

    large = upload("board.zip")
    large.define_singleton_method(:size) { Project::MAX_KICAD_FILE_SIZE + 1 }
    assert_match(/board.zip is too large/, ProjectKicadFiles.upload_error([ large ]))
  end

  private

  def fixture(name)
    file_fixture("kicad/#{name}").binread
  end

  def fixture_path(name)
    file_fixture("kicad/#{name}").to_s
  end

  def upload(filename)
    Rack::Test::UploadedFile.new(StringIO.new("x"), "application/octet-stream", original_filename: filename)
  end

  def zip_file(entries)
    file = Tempfile.new([ "project", ".zip" ], binmode: true)
    Zip::OutputStream.open(file.path) do |zip|
      entries.each do |name, content|
        zip.put_next_entry(name)
        zip.write(content)
      end
    end
    file
  end
end
