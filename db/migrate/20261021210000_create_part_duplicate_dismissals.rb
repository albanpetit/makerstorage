class CreatePartDuplicateDismissals < ActiveRecord::Migration[8.1]
  def change
    # Two parts someone marked as "not duplicates", so the duplicate finder stops
    # pairing them. Stored once per pair, lower id first.
    create_table :part_duplicate_dismissals do |t|
      t.references :part, null: false, foreign_key: true
      t.references :other_part, null: false, foreign_key: { to_table: :parts }
      t.timestamps
    end
    add_index :part_duplicate_dismissals, %i[part_id other_part_id], unique: true,
              name: "index_part_duplicate_dismissals_on_pair"
  end
end
