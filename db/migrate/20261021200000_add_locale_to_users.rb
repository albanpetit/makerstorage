class AddLocaleToUsers < ActiveRecord::Migration[8.1]
  def change
    # UI language picked in the profile ("en", "fr"); nil follows the browser.
    add_column :users, :locale, :string
  end
end
