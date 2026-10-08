# The CSV importer matches categories case-insensitively ("resistors" is the
# existing "Resistors"), but the name rule was case-sensitive, so both could
# exist side by side and an import would land in either. Make the rule
# case-insensitive, backed by an index on LOWER(name). Existing case-only
# duplicates are renamed ("resistors (2)") rather than merged or deleted, so no
# part changes category behind the operator's back.
class MakeCategoryNamesUniqueRegardlessOfCase < ActiveRecord::Migration[8.1]
  def up
    duplicates = select_rows(<<~SQL)
      SELECT organization_id, LOWER(name) FROM categories
      GROUP BY organization_id, LOWER(name) HAVING COUNT(*) > 1
    SQL

    duplicates.each do |organization_id, lowered|
      org = Integer(organization_id)
      rows = select_rows(<<~SQL)
        SELECT id, name FROM categories
        WHERE organization_id = #{org} AND LOWER(name) = #{quote(lowered)}
        ORDER BY id
      SQL

      rows.drop(1).each do |id, name|
        suffix = 2
        suffix += 1 while select_value("SELECT 1 FROM categories WHERE organization_id = #{org} AND LOWER(name) = LOWER(#{quote("#{name} (#{suffix})")})")
        execute "UPDATE categories SET name = #{quote("#{name} (#{suffix})")} WHERE id = #{Integer(id)}"
      end
    end

    remove_index :categories, [ :organization_id, :name ]
    add_index :categories, "organization_id, LOWER(name)", unique: true, name: "index_categories_on_organization_id_and_lower_name"
  end

  def down
    remove_index :categories, name: "index_categories_on_organization_id_and_lower_name"
    add_index :categories, [ :organization_id, :name ], unique: true
  end
end
