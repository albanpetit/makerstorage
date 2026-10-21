require "test_helper"

class ProjectFilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @org = @user.organizations.first
    @category = create_category(organization: @org)
    @cap = create_part(organization: @org, category: @category, name: "MLCC 100nF", sku: "C14663")
    @opamp = create_part(organization: @org, category: @category, name: "LM358", mpn: "LM358DR")
    @resistor = create_part(organization: @org, category: @category, name: "Resistor 10k")
  end

  # -- Creating a project from its KiCad files --------------------------------

  test "create from loose KiCad files attaches them and reads the BOM from the schematics" do
    sign_in @user
    assert_difference -> { Project.count } => 1, -> { ProjectLine.count } => 3 do
      post projects_path, params: { files: [ kicad("board/board.kicad_pro"), kicad("board/board.kicad_sch"), kicad("board/sensor.kicad_sch") ] }
    end

    project = Project.order(:id).last
    assert_redirected_to project_path(project)
    assert_match(/Imported 3 BOM lines from the schematic/, flash[:notice])
    assert_equal "board", project.name
    assert_equal %w[board.kicad_pro board.kicad_sch sensor.kicad_sch], project.kicad_files.map { |f| f.filename.to_s }.sort
    assert project.kicad_files.all? { |f| f.content_type == Project::KICAD_FILE_TYPE }

    by_value = project.project_lines.index_by(&:value)
    assert_equal [ @cap, "sku" ], [ by_value["100nF"].part, by_value["100nF"].match_type ]
    assert_equal [ @opamp, "mpn" ], [ by_value["LM358"].part, by_value["LM358"].match_type ]
    assert_equal [ nil, 4, "R1, R2, R3, R103" ], [ by_value["10k"].part, by_value["10k"].quantity, by_value["10k"].designators ]
  end

  test "create from a zipped project" do
    sign_in @user
    post projects_path, params: { name: "Rover", files: [ zip_upload("rover.zip", "rover/board.kicad_sch" => fixture("board/board.kicad_sch")) ] }

    project = Project.order(:id).last
    assert_equal "Rover", project.name
    assert_equal [ Project::ZIP_TYPE ], project.kicad_files.map(&:content_type)
    assert_equal 3, project.project_lines.count
  end

  test "create from KiCad files without a schematic makes a project with an empty BOM" do
    sign_in @user
    assert_difference -> { Project.count } => 1, -> { ProjectLine.count } => 0 do
      post projects_path, params: { files: [ kicad("board/board.kicad_pro") ] }
    end
    assert_match(/No schematic/, flash[:notice])
    assert_equal 1, Project.order(:id).last.kicad_files.count
  end

  test "create refuses files that aren't KiCad files, and unreadable schematics" do
    sign_in @user
    assert_no_difference -> { Project.count } do
      post projects_path, params: { files: [ kicad("board/board.kicad_sch"), text_upload("notes.txt", "hi") ] }
    end
    assert_match(/notes.txt isn't a KiCad file/, flash[:alert])

    assert_no_difference -> { Project.count } do
      post projects_path, params: { files: [ text_upload("old.kicad_sch", "EESchema Schematic File Version 4") ] }
    end
    assert_match(/old.kicad_sch isn't a KiCad schematic/, flash[:alert])
  end

  test "viewers cannot create a project from KiCad files" do
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer
    post "/organizations/#{@org.id}/switch"

    assert_no_difference -> { Project.count } do
      post projects_path, params: { files: [ kicad("board/board.kicad_sch") ] }
    end
  end

  # -- Files on an existing project -------------------------------------------

  test "adding files to a project without a BOM fills it from the schematic" do
    project = create_project(organization: @org)

    sign_in @user
    post project_project_files_path(project), params: { files: [ kicad("board/board.kicad_sch") ] }

    assert_redirected_to project_path(project)
    assert_match(/Added 1 file\. Imported 3 BOM lines/, flash[:notice])
    assert_equal 3, project.project_lines.count
    assert_equal [ "board.kicad_sch" ], project.kicad_files.map { |f| f.filename.to_s }
  end

  test "adding files to a project with a BOM leaves its lines alone" do
    project = create_project(organization: @org)
    line = project.project_lines.create!(part: @cap, quantity: 7, match_type: "manual")

    sign_in @user
    post project_project_files_path(project), params: { files: [ kicad("board/board.kicad_sch"), text_upload("board.kicad_pcb", "(kicad_pcb (version 20240108))") ] }

    assert_equal "Added 2 files.", flash[:notice]
    assert_equal [ line ], project.project_lines.reload
    assert_equal 2, project.kicad_files.count
  end

  test "adding files refuses other files and stops at the file limit" do
    project = create_project(organization: @org)

    sign_in @user
    post project_project_files_path(project), params: { files: [ text_upload("notes.txt", "x") ] }
    assert_match(/isn't a KiCad file/, flash[:alert])

    stub_const(Project, :MAX_KICAD_FILES, 1) do
      post project_project_files_path(project), params: { files: [ kicad("board/board.kicad_pro"), kicad("board/board.kicad_sch") ] }
    end
    assert_match(/at most 1 files/, flash[:alert])
    assert_not project.kicad_files.attached?
  end

  test "import_bom replaces the lines from the schematics, keeping parts picked by hand" do
    project = create_project(organization: @org, status: "confirmed", reserved_at: 1.hour.ago, checked_at: 1.hour.ago)
    project.kicad_files.attach(io: file_fixture("kicad/board/board.kicad_sch").open, filename: "board.kicad_sch",
                               content_type: Project::KICAD_FILE_TYPE)
    project.project_lines.create!(part: @resistor, value: "10k", footprint: "Resistor_SMD:R_0603_1608Metric",
                                  quantity: 2, match_type: "manual")
    project.project_lines.create!(designation: "Removed part", quantity: 1, match_type: "none")

    sign_in @user
    post import_bom_project_project_files_path(project)

    assert_redirected_to project_path(project)
    assert_match(/BOM updated from the schematic: 3 lines/, flash[:notice])
    project.reload
    assert_equal [ "draft", nil, nil ], [ project.status, project.reserved_at, project.checked_at ]
    resistors = project.project_lines.find_by!(value: "10k")
    assert_equal [ @resistor, "manual", 2 ], [ resistors.part, resistors.match_type, resistors.quantity ]
    assert_not project.project_lines.exists?(designation: "Removed part")
  end

  test "import_bom without a schematic changes nothing" do
    project = create_project(organization: @org)
    project.kicad_files.attach(io: file_fixture("kicad/board/board.kicad_pro").open, filename: "board.kicad_pro",
                               content_type: Project::KICAD_FILE_TYPE)
    line = project.project_lines.create!(part: @cap, quantity: 1, match_type: "sku")

    sign_in @user
    post import_bom_project_project_files_path(project)

    assert_match(/No schematic/, flash[:alert])
    assert_equal [ line ], project.project_lines.reload
  end

  test "destroy removes one file" do
    project = create_project(organization: @org)
    project.kicad_files.attach(io: file_fixture("kicad/board/board.kicad_pro").open, filename: "board.kicad_pro",
                               content_type: Project::KICAD_FILE_TYPE)

    sign_in @user
    delete project_project_file_path(project, project.kicad_files.first)

    assert_redirected_to project_path(project)
    assert_not project.reload.kicad_files.attached?
  end

  test "the project page lists its files, served to members only" do
    project = create_project(organization: @org)
    project.kicad_files.attach(io: file_fixture("kicad/board/board.kicad_sch").open, filename: "board.kicad_sch",
                               content_type: Project::KICAD_FILE_TYPE)

    sign_in @user
    get project_path(project)
    files = inertia_props.dig("project", "files")
    assert_equal [ "board.kicad_sch" ], files.map { |f| f["filename"] }
    assert inertia_props.dig("project", "files_have_schematics")

    get files.first["url"]
    assert_response :success
    assert_match(/attachment/, response.headers["Content-Disposition"])

    sign_in create_user
    get files.first["url"]
    assert_response :not_found
  end

  test "viewers can't change files, and another organization's project is not found" do
    project = create_project(organization: @org)
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer
    post "/organizations/#{@org.id}/switch"
    post project_project_files_path(project), params: { files: [ kicad("board/board.kicad_sch") ] }
    assert_match(/read-only/i, flash[:alert])
    assert_not project.kicad_files.attached?

    foreign = create_project(organization: create_organization)
    sign_in @user
    post project_project_files_path(foreign), params: { files: [ kicad("board/board.kicad_sch") ] }
    assert_response :not_found
  end

  private

  def fixture(name)
    file_fixture("kicad/#{name}").binread
  end

  def kicad(name)
    Rack::Test::UploadedFile.new(file_fixture("kicad/#{name}"), "application/octet-stream")
  end

  def text_upload(filename, content)
    Rack::Test::UploadedFile.new(StringIO.new(content), "application/octet-stream", original_filename: filename)
  end

  def zip_upload(filename, entries)
    file = Tempfile.new([ "project", ".zip" ], binmode: true)
    Zip::OutputStream.open(file.path) do |zip|
      entries.each do |name, content|
        zip.put_next_entry(name)
        zip.write(content)
      end
    end
    Rack::Test::UploadedFile.new(file.path, "application/zip", original_filename: filename)
  end

  def stub_const(mod, name, value)
    original = mod.const_get(name)
    mod.send(:remove_const, name)
    mod.const_set(name, value)
    yield
  ensure
    mod.send(:remove_const, name)
    mod.const_set(name, original)
  end

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end
end
