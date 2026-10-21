class AddGithubLinkToProjects < ActiveRecord::Migration[8.1]
  def change
    # The GitHub repository a project's KiCad files come from: "owner/name",
    # plus an optional branch/tag/commit (blank = the default branch) and a
    # folder inside the repository (blank = its root).
    add_column :projects, :github_repository, :string
    add_column :projects, :github_ref, :string
    add_column :projects, :github_path, :string
    # The commit the files were last fetched from, and when.
    add_column :projects, :github_synced_sha, :string
    add_column :projects, :github_synced_at, :datetime

    # Personal access token (read-only contents) used for every GitHub request,
    # needed for private repositories; stored encrypted.
    add_column :organizations, :github_token, :string
  end
end
