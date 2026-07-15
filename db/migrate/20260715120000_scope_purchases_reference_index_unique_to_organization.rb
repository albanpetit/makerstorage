class ScopePurchasesReferenceIndexUniqueToOrganization < ActiveRecord::Migration[8.1]
  def change
    # Replace the plain lookup index with a per-organization unique one so the
    # model's `uniqueness: { scope: :organization_id }` validation is enforced at
    # the DB level too, closing the TOCTOU gap where two concurrent orders could
    # both pass the validation and persist the same reference. Blank/nil
    # references stay unconstrained to match the validation's `allow_blank`.
    remove_index :purchases, :reference, name: "index_purchases_on_reference"
    add_index :purchases, [ :organization_id, :reference ], unique: true,
      where: "reference IS NOT NULL AND reference != ''"
  end
end
