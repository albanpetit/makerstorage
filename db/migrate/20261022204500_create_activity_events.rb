class CreateActivityEvents < ActiveRecord::Migration[8.1]
  def change
    # Who changed what in an organization (Activity page, admins only). The
    # subject is kept as a plain type + id + label, not a polymorphic
    # association: the label still reads once the record is deleted.
    create_table :activity_events do |t|
      t.references :organization, null: false, foreign_key: true, index: false
      t.references :user, foreign_key: true
      t.string :user_name
      t.string :action, null: false
      t.string :subject_type
      t.integer :subject_id
      t.string :subject_label
      t.json :details, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :activity_events, %i[organization_id created_at]
    add_index :activity_events, %i[organization_id subject_type subject_id], name: "index_activity_events_on_subject"
  end
end
