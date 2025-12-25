class CreateSuppliers < ActiveRecord::Migration[8.1]
  def change
    create_table :suppliers do |t|
      t.references :organization, null: false, foreign_key: true

      t.string :name, null: false
      t.string :website
      t.string :email
      t.string :phone

      # Address
      t.string :address_line1
      t.string :address_line2
      t.string :city
      t.string :postcode
      t.string :country

      t.text :notes

      t.timestamps
    end

    add_index :suppliers, [ :organization_id, :name ]
  end
end
