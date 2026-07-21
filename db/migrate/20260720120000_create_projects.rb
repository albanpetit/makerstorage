class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :description
      t.string :reference
      t.string :status, null: false, default: "draft"
      t.datetime :checked_at

      t.timestamps
    end

    add_index :projects, [ :organization_id, :reference ], unique: true,
      where: "reference IS NOT NULL AND reference != ''"
  end
end
