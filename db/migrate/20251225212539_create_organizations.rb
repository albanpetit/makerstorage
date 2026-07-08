class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :name, null: false

      # Contact information
      t.string :email
      t.string :phone
      t.string :website

      # Address
      t.string :address_line1
      t.string :address_line2
      t.string :city
      t.string :postcode
      t.string :country

      # Internal reference (IPN) numbering scheme
      t.string :ipn_prefix, default: "MS", null: false
      t.boolean :ipn_use_category_code, default: true, null: false
      t.string :ipn_separator, default: "-", null: false
      t.integer :ipn_digits, default: 5, null: false
      t.integer :ipn_next_sequence, default: 1, null: false

      # General settings
      t.string :currency, default: "EUR", null: false
      t.string :timezone, default: "Europe/Paris", null: false
      t.integer :default_low_stock_threshold, default: 50, null: false
      t.boolean :allow_negative_stock, default: false, null: false

      t.timestamps
    end

    add_index :organizations, :name
    add_index :organizations, :email
  end
end
