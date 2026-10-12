# Email verification (Devise :confirmable) starts now; accounts created before
# it can't be asked to confirm retroactively, so they count as confirmed.
class ConfirmExistingUsers < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE users SET confirmed_at = created_at WHERE confirmed_at IS NULL"
  end

  def down
    # Irreversible in substance (nothing records which users were backfilled),
    # and harmless to leave: a confirmed_at only matters with :confirmable on.
  end
end
