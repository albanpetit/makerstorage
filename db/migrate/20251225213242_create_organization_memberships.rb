class CreateOrganizationMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :organization_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.references :invited_by, foreign_key: { to_table: :users }, null: true

      t.string :role, null: false, default: 'member'
      t.string :invitation_token
      t.datetime :invitation_sent_at
      t.datetime :invitation_accepted_at
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :organization_memberships, [ :user_id, :organization_id ],
              unique: true,
              name: 'index_org_memberships_on_user_and_org'
    add_index :organization_memberships, :invitation_token, unique: true
    add_index :organization_memberships, :active
  end
end
