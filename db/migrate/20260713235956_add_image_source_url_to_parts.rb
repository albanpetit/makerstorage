class AddImageSourceUrlToParts < ActiveRecord::Migration[8.1]
  def change
    add_column :parts, :image_source_url, :string
  end
end
