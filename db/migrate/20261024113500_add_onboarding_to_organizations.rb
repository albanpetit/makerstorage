class AddOnboardingToOrganizations < ActiveRecord::Migration[8.1]
  def up
    # Guided onboarding (OrganizationTemplate, dashboard): the template a new
    # organization started from, when its "first steps" list was put away, and
    # whether it's a throwaway demo (OrganizationDemo).
    add_column :organizations, :onboarding_template, :string
    add_column :organizations, :onboarding_dismissed_at, :datetime
    add_column :organizations, :demo, :boolean, default: false, null: false

    # Organizations already in use never saw the new list: the old one went
    # away with the first stock movement, so keep it away.
    execute <<~SQL.squish
      UPDATE organizations SET onboarding_dismissed_at = CURRENT_TIMESTAMP
      WHERE EXISTS (SELECT 1 FROM stock_movements WHERE stock_movements.organization_id = organizations.id)
    SQL
  end

  def down
    remove_column :organizations, :demo
    remove_column :organizations, :onboarding_dismissed_at
    remove_column :organizations, :onboarding_template
  end
end
