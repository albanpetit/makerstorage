class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :name, null: false

      # Contact information
      t.string :email
      t.string :phone

      # Address
      t.string :address_line1
      t.string :address_line2
      t.string :city
      t.string :postcode
      t.string :country

      t.timestamps
    end

    add_index :organizations, :name
    add_index :organizations, :email
  end
end
