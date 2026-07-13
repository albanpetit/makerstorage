# frozen_string_literal: true

class AddPersonalToOrganizations < ActiveRecord::Migration[8.1]
  def up
    add_column :organizations, :personal, :boolean, default: false, null: false

    # Backfill: the organization auto-created at signup is named
    # "<firstname>'s Organization" and owned by that user. Mark those personal
    # so the deletion guard protects existing accounts, not just new ones.
    execute(<<~SQL)
      UPDATE organizations
      SET personal = 1
      WHERE id IN (
        SELECT om.organization_id
        FROM organization_memberships om
        JOIN users u ON u.id = om.user_id
        JOIN organizations o ON o.id = om.organization_id
        WHERE om.role = 'owner'
          AND o.name = u.firstname || '''s Organization'
      )
    SQL
  end

  def down
    remove_column :organizations, :personal
  end
end
