class AddKicadFieldsToProjectLines < ActiveRecord::Migration[8.1]
  def change
    add_column :project_lines, :designators, :text
    add_column :project_lines, :value, :string
    add_column :project_lines, :footprint, :string
  end
end
