# frozen_string_literal: true

class AddIpnGenerationModeToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :ipn_generation_mode, :string, default: "incremental", null: false
    add_column :organizations, :ipn_charset, :string, default: "numeric", null: false
  end
end
