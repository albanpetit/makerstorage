class CreatePartParameters < ActiveRecord::Migration[8.1]
  def change
    # The organization's parameter vocabulary: "Resistance" in Ω, "Dielectric"
    # as text. Numeric values are stored in the unit itself (no prefix), so
    # they compare and filter across "4k7", "4.7 kΩ" and "4700".
    create_table :parameter_definitions do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :value_type, null: false, default: "number"
      t.string :unit
      t.text :description
      t.timestamps
    end
    add_index :parameter_definitions, "organization_id, LOWER(name)", unique: true,
              name: "index_parameter_definitions_on_organization_id_and_lower_name"

    # A category's template: the parameters the part form proposes for its
    # parts (sub-categories inherit their parents').
    create_table :category_parameters do |t|
      t.references :category, null: false, foreign_key: true
      t.references :parameter_definition, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :category_parameters, %i[category_id parameter_definition_id], unique: true,
              name: "index_category_parameters_on_category_and_definition"

    # One value per part and parameter: the text as typed, and for number
    # parameters its value in the definition's unit.
    create_table :part_parameters do |t|
      t.references :part, null: false, foreign_key: true
      t.references :parameter_definition, null: false, foreign_key: true
      t.string :value, null: false
      t.float :numeric_value
      t.timestamps
    end
    add_index :part_parameters, %i[part_id parameter_definition_id], unique: true,
              name: "index_part_parameters_on_part_and_definition"
    add_index :part_parameters, %i[parameter_definition_id numeric_value],
              name: "index_part_parameters_on_definition_and_numeric_value"
  end
end
