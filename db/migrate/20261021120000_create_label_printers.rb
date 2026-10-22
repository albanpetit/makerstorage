class CreateLabelPrinters < ActiveRecord::Migration[8.1]
  def change
    # Network label printers the server sends raw jobs to (see LabelPrinter).
    create_table :label_printers do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :protocol, null: false
      t.string :host, null: false
      t.integer :port, null: false, default: 9100
      # Brother QL: a key of LabelPrinting::BrotherQl::MEDIA. Zebra: unused.
      t.string :media
      # Label size: Zebra labels, and the length cut from Brother continuous rolls.
      t.decimal :width_mm, precision: 6, scale: 1
      t.decimal :length_mm, precision: 6, scale: 1
      t.integer :dpi
      t.timestamps
    end
  end
end
