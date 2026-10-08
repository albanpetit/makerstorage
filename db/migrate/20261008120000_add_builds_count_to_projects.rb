class AddBuildsCountToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :builds_count, :integer, default: 0, null: false
    add_column :projects, :last_built_at, :datetime
  end
end
