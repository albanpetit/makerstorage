class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :categories }, null: true

      t.string :name, null: false
      t.text :description
      t.string :icon
      t.string :color

      t.timestamps
    end

    add_index :categories, [ :organization_id, :name ]
  end
end
