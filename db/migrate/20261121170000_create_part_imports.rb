# A CSV import of parts, run in the background (PartCsvImportJob): its
# progress and outcome, polled by the inventory page.
class CreatePartImports < ActiveRecord::Migration[8.1]
  def change
    create_table :part_imports do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :filename, null: false
      # Names the uploaded file in tmp/imports/ (ids repeat across databases).
      t.string :file_token, null: false
      t.string :status, null: false, default: "queued"
      t.integer :total_rows, null: false, default: 0
      t.integer :processed_rows, null: false, default: 0
      t.integer :created_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.string :error
      t.datetime :seen_at
      t.timestamps
    end
    add_index :part_imports, [ :organization_id, :user_id, :created_at ]
  end
end
