# Box & bag numbering (Organization ipn_generation_mode "box_bag"): a bag is a
# storage zone numbered inside its box (A-1, A-2, …), and a part holds at most
# one bag, whose code is the part's IPN.
class AddBoxBagStorage < ActiveRecord::Migration[8.1]
  def change
    add_column :storage_locations, :position, :integer

    add_reference :parts, :bag, foreign_key: { to_table: :storage_locations }, index: false
    add_index :parts, :bag_id, unique: true, where: "bag_id IS NOT NULL"
    # When the part took its bag: a bag only frees up once the part has been
    # emptied out of it since then (see Organization#free_bags).
    add_column :parts, :bag_assigned_at, :datetime
  end
end
