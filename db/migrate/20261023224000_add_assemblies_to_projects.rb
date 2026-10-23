class AddAssembliesToProjects < ActiveRecord::Migration[8.1]
  def change
    # A BOM line can use another project of the organization as a sub-assembly
    # instead of a part (ProjectStructure).
    add_reference :project_lines, :subproject, foreign_key: { to_table: :projects }
    # The inventory part one built kit of the project becomes: building credits
    # it, and a parent project using this one as a sub-assembly takes it from stock.
    add_reference :projects, :output_part, foreign_key: { to_table: :parts }
  end
end
