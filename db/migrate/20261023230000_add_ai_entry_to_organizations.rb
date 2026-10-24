class AddAiEntryToOrganizations < ActiveRecord::Migration[8.1]
  # AI-assisted part entry (PartExtraction): the organization's own Anthropic
  # API key (encrypted, write-only) and the Claude model it pays for.
  def change
    add_column :organizations, :anthropic_api_key, :string
    add_column :organizations, :ai_model, :string, default: "claude-opus-5-5", null: false
  end
end
