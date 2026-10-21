class CreateLoans < ActiveRecord::Migration[8.1]
  def change
    create_table :loans do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :reference
      # A member of the organization, or anyone else by name. The name is kept
      # either way, so the loan still reads right once the account is gone.
      t.references :borrower, foreign_key: { to_table: :users }
      t.string :borrower_name, null: false
      t.string :borrower_contact
      t.references :lent_by, foreign_key: { to_table: :users }
      t.date :due_on
      t.text :notes
      t.datetime :closed_at
      t.timestamps
    end
    add_index :loans, %i[organization_id reference], unique: true, where: "reference IS NOT NULL AND reference != ''"
    add_index :loans, %i[organization_id closed_at due_on]

    create_table :loan_lines do |t|
      t.references :loan, null: false, foreign_key: true
      t.references :part, null: false, foreign_key: true
      # Where the items were taken from: where returns go back by default.
      t.references :storage_location, foreign_key: true
      t.integer :quantity, null: false
      t.integer :returned_quantity, null: false, default: 0
      t.integer :lost_quantity, null: false, default: 0
      t.timestamps
    end

    add_column :organizations, :default_loan_days, :integer, null: false, default: 14
    add_column :organizations, :notify_overdue_loans, :boolean, null: false, default: true
  end
end
