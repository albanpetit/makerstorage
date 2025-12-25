class CreateTags < ActiveRecord::Migration[8.1]
  def change
    create_table :tags do |t|
      t.references :organization, null: false, foreign_key: true

      t.string :name, null: false
      t.text :description
      t.string :color

      t.timestamps
    end

    add_index :tags, [ :organization_id, :name ], unique: true
  end
end
