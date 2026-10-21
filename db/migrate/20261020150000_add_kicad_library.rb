class AddKicadLibrary < ActiveRecord::Migration[8.1]
  def change
    # KiCad HTTP library access: one token per organization, of which only the
    # SHA-256 digest is stored (the token is shown once, in the library file).
    add_column :organizations, :kicad_token_digest, :string
    add_column :organizations, :kicad_token_created_at, :datetime
    add_column :organizations, :kicad_token_last_used_at, :datetime
    add_index :organizations, :kicad_token_digest, unique: true

    # "Library:Name" references into the user's KiCad libraries. A part's own
    # value wins, then its category's (or the nearest ancestor's), then a guess
    # from the category name (see KicadLibrary).
    add_column :categories, :kicad_symbol, :string
    add_column :footprints, :kicad_footprint, :string
    add_column :parts, :kicad_symbol, :string
    add_column :parts, :kicad_footprint, :string
  end
end
