require "test_helper"

class ProjectGithubControllerTest < ActionDispatch::IntegrationTest
  SHA1 = "a" * 40
  SHA2 = "b" * 40

  setup do
    @user = create_user
    @org = @user.organizations.first
    @project = create_project(organization: @org)
  end

  test "linking a project fetches its KiCad files and BOM, taking the branch and folder from a URL" do
    sign_in @user
    fake = FakeGithub.new(commits: { "v2" => SHA1 }, archives: { SHA1 => repo_files })

    with_fake_github(fake) do
      patch project_github_path(@project), params: { repository: "https://github.com/maker/rover/tree/v2/hw" }
    end

    assert_redirected_to project_path(@project)
    assert_equal "Fetched 3 KiCad files from maker/rover/hw@v2 (aaaaaaa). BOM updated from the schematic: 3 lines. Review the matches below.", flash[:notice]
    @project.reload
    assert_equal [ "maker/rover", "v2", "hw", SHA1 ], [ @project.github_repository, @project.github_ref, @project.github_path, @project.github_synced_sha ]
    assert_equal 3, @project.project_lines.count
  end

  test "explicit branch and folder fields win over the URL's" do
    sign_in @user
    fake = FakeGithub.new(commits: { "dev" => SHA1 }, archives: { SHA1 => repo_files })

    with_fake_github(fake) do
      patch project_github_path(@project), params: { repository: "maker/rover", ref: "dev", path: "/hw/" }
    end

    assert_equal [ "dev", "hw" ], @project.reload.then { |p| [ p.github_ref, p.github_path ] }
  end

  test "a link GitHub can't serve is kept, with the error shown" do
    sign_in @user
    with_fake_github(FakeGithub.new(error: "Could not find maker/rover on GitHub.")) do
      patch project_github_path(@project), params: { repository: "maker/rover" }
    end

    assert_equal "Could not find maker/rover on GitHub.", flash[:alert]
    assert_equal "maker/rover", @project.reload.github_repository
    assert_nil @project.github_synced_sha
  end

  test "an invalid repository is refused" do
    sign_in @user
    patch project_github_path(@project), params: { repository: "not a repo" }
    assert_match(/Github repository must look like owner\/name/, flash[:alert])

    patch project_github_path(@project), params: { repository: "" }
    assert_match(/Enter a GitHub repository/, flash[:alert])
    assert_nil @project.reload.github_repository
  end

  test "sync fetches a new commit, or says it's up to date" do
    sign_in @user
    @project.update!(github_repository: "maker/rover", github_path: "hw")
    fake = FakeGithub.new(commits: { nil => SHA1 }, archives: { SHA1 => repo_files })

    with_fake_github(fake) { post sync_project_github_path(@project) }
    assert_match(/Fetched 3 KiCad files/, flash[:notice])

    with_fake_github(fake) { post sync_project_github_path(@project) }
    assert_equal "Already up to date with maker/rover/hw (aaaaaaa).", flash[:notice]

    fake = FakeGithub.new(commits: { nil => SHA2 }, archives: { SHA2 => repo_files })
    with_fake_github(fake) { post sync_project_github_path(@project) }
    assert_equal "Fetched 3 KiCad files from maker/rover/hw (bbbbbbb). The BOM hasn't changed.", flash[:notice]
  end

  test "changing the folder fetches again at the same commit" do
    sign_in @user
    @project.update!(github_repository: "maker/rover", github_path: "hw", github_synced_sha: SHA1)
    @project.kicad_files.attach(io: StringIO.new("PK"), filename: "rover.zip", content_type: Project::ZIP_TYPE, metadata: { "github_sha" => SHA1 })
    fake = FakeGithub.new(commits: { nil => SHA1 }, archives: { SHA1 => repo_files })

    with_fake_github(fake) { patch project_github_path(@project), params: { repository: "maker/rover", path: "hw/sub" } }

    assert_match(/Fetched 1 KiCad file from maker\/rover\/hw\/sub/, flash[:notice])
  end

  test "unlinking keeps the fetched files" do
    sign_in @user
    @project.update!(github_repository: "maker/rover", github_synced_sha: SHA1)
    @project.kicad_files.attach(io: StringIO.new("PK"), filename: "rover.zip", content_type: Project::ZIP_TYPE)

    delete project_github_path(@project)

    assert_match(/Unlinked from GitHub/, flash[:notice])
    @project.reload
    assert_nil @project.github_repository
    assert_nil @project.github_synced_sha
    assert_equal 1, @project.kicad_files.count
  end

  test "new project from a GitHub repository" do
    sign_in @user
    fake = FakeGithub.new(commits: { nil => SHA1 }, archives: { SHA1 => repo_files })

    assert_difference -> { Project.count } => 1 do
      with_fake_github(fake) { post projects_path, params: { repository: "maker/rover", path: "hw" } }
    end

    project = Project.order(:id).last
    assert_redirected_to project_path(project)
    assert_equal [ "hw", "maker/rover", SHA1, 3 ], [ project.name, project.github_repository, project.github_synced_sha, project.project_lines.count ]
    assert project.reference.present?
  end

  test "new project from GitHub is not kept when the fetch fails" do
    sign_in @user
    assert_no_difference -> { Project.count } do
      with_fake_github(FakeGithub.new(error: "GitHub refused access to maker/rover.")) do
        post projects_path, params: { name: "Rover", repository: "maker/rover" }
      end
    end
    assert_redirected_to projects_path
    assert_equal "GitHub refused access to maker/rover.", flash[:alert]
  end

  test "the project page shows the link" do
    sign_in @user
    @project.update!(github_repository: "maker/rover", github_ref: "v2", github_path: "hw", github_synced_sha: SHA1, github_synced_at: Time.current)

    get project_path(@project)

    github = inertia_props.dig("project", "github")
    assert_equal "maker/rover/hw@v2", github["location"]
    assert_equal "https://github.com/maker/rover/tree/v2/hw", github["url"]
    assert_equal "https://github.com/maker/rover/commit/#{SHA1}", github["commit_url"]
    assert_equal false, inertia_props.dig("project", "github_token_configured")
  end

  test "viewers can't link or sync, and other organizations' projects are out of reach" do
    viewer = create_user
    OrganizationMembership.create!(organization: @org, user: viewer, role: "viewer")
    sign_in viewer
    patch project_github_path(@project), params: { repository: "maker/rover" }
    post sync_project_github_path(@project)
    assert_nil @project.reload.github_repository

    outsider = create_user
    sign_in outsider
    patch project_github_path(@project), params: { repository: "maker/rover" }
    assert_response :not_found
    assert_nil @project.reload.github_repository
  end

  private

  def inertia_props
    JSON.parse(@response.body[/data-page="app" type="application\/json"[^>]*>(.*?)<\/script>/m, 1])["props"]
  end

  def repo_files
    {
      "hw/board.kicad_pro" => file_fixture("kicad/board/board.kicad_pro").binread,
      "hw/board.kicad_sch" => file_fixture("kicad/board/board.kicad_sch").binread,
      "hw/sub/sensor.kicad_sch" => file_fixture("kicad/board/sensor.kicad_sch").binread
    }
  end
end
