class CreatePartAlternatives < ActiveRecord::Migration[8.1]
  def change
    # Two parts that can stand in for each other (a second source, an
    # equivalent from another maker). Stored once per pair, lower id first;
    # the link reads both ways.
    create_table :part_alternatives do |t|
      t.references :part, null: false, foreign_key: true
      t.references :alternative_part, null: false, foreign_key: { to_table: :parts }
      t.string :note
      t.timestamps
    end
    add_index :part_alternatives, %i[part_id alternative_part_id], unique: true,
              name: "index_part_alternatives_on_pair"
  end
end
