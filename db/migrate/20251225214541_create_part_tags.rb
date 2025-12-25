class CreatePartTags < ActiveRecord::Migration[8.1]
  def change
    create_table :part_tags do |t|
      t.references :part, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true

      t.timestamps
    end

    add_index :part_tags, [ :part_id, :tag_id ], unique: true
  end
end
