class CreateProjectLines < ActiveRecord::Migration[8.1]
  def change
    create_table :project_lines do |t|
      t.references :project, null: false, foreign_key: true
      t.references :part, null: true, foreign_key: true
      t.string :raw_reference
      t.string :designation
      t.integer :quantity, null: false, default: 1
      t.string :match_type, null: false, default: "none"

      t.timestamps
    end
  end
end
