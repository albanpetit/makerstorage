# Category names were only unique per organization by validation, so two
# concurrent creations (e.g. two CSV imports naming the same new category) could
# both pass it. Back the rule with the index. Any duplicate that already slipped
# through is renamed ("Resistors (2)") rather than merged or deleted, so no part
# changes category behind the operator's back.
class MakeCategoryNamesUniquePerOrganization < ActiveRecord::Migration[8.1]
  def up
    duplicates = select_rows(<<~SQL)
      SELECT organization_id, name FROM categories
      GROUP BY organization_id, name HAVING COUNT(*) > 1
    SQL

    duplicates.each do |organization_id, name|
      ids = select_values(<<~SQL)
        SELECT id FROM categories
        WHERE organization_id = #{Integer(organization_id)} AND name = #{quote(name)}
        ORDER BY id
      SQL

      ids.drop(1).each_with_index do |id, index|
        suffix = index + 2
        suffix += 1 while select_value("SELECT 1 FROM categories WHERE organization_id = #{Integer(organization_id)} AND name = #{quote("#{name} (#{suffix})")}")
        execute "UPDATE categories SET name = #{quote("#{name} (#{suffix})")} WHERE id = #{Integer(id)}"
      end
    end

    remove_index :categories, [ :organization_id, :name ]
    add_index :categories, [ :organization_id, :name ], unique: true
  end

  def down
    remove_index :categories, [ :organization_id, :name ]
    add_index :categories, [ :organization_id, :name ]
  end
end
