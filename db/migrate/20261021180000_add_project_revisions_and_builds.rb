class AddProjectRevisionsAndBuilds < ActiveRecord::Migration[8.1]
  def change
    # Free-form revision label ("A", "B", "v2"…); duplicating a project as a new
    # revision copies its lines and bumps this.
    add_column :projects, :revision, :string

    # One row per build of a project: how many kits, when, by whom. The "out"
    # movements a build wrote point back at it.
    create_table :project_builds do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.datetime :built_at, null: false
      t.string :note
      t.timestamps
    end

    add_reference :stock_movements, :project_build, foreign_key: true
  end
end
