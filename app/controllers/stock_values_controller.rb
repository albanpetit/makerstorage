# frozen_string_literal: true

require "csv"

# Stock value: what the stock on hand is worth, by category, top-level zone and
# part, valued at current or purchase prices (StockValuation), plus a CSV.
class StockValuesController < ApplicationController
  include Auth
  include CsvText

  # Parts listed on the page; the CSV has them all.
  PAGE_PARTS = 100

  before_action :verify_organization_access

  def show
    valuation = StockValuation.new(current_organization, method: params[:method])

    respond_to do |format|
      format.html do
        render inertia: "stock_values/show", props: {
          valuation_method: valuation.valuation_method,
          currency: current_organization.currency,
          total: valuation.total.to_f,
          parts_count: valuation.rows.size,
          purchase_priced_count: valuation.rows.count { |row| row.source == "purchase" },
          unpriced_count: valuation.unpriced_rows.size,
          categories: valuation.by_category.map do |entry|
            { id: entry[:category]&.id, name: entry[:category]&.name, color: entry[:category]&.color, value: entry[:value].to_f, parts: entry[:parts] }
          end,
          zones: valuation.by_root_zone.map do |entry|
            { id: entry[:zone].id, name: entry[:zone].name, value: entry[:value].to_f, parts: entry[:parts] }
          end,
          parts: valuation.rows.first(PAGE_PARTS).map { |row| serialize_row(row) },
          unpriced_parts: valuation.unpriced_rows.first(PAGE_PARTS).map { |row| serialize_row(row) }
        }
      end
      format.csv do
        send_data csv_for(valuation), filename: "stock-value-#{valuation.valuation_method}-#{current_organization.local_date.iso8601}.csv", type: "text/csv"
      end
    end
  end

  private

  def serialize_row(row)
    {
      id: row.part.id,
      reference: row.part.reference,
      ipn: row.part.ipn,
      name: row.part.name,
      category: row.part.category&.name,
      quantity: row.quantity,
      unit_value: row.unit_value&.to_f,
      value: row.value.to_f,
      source: row.source
    }
  end

  def csv_for(valuation)
    csv = +CSV.generate_line([ "Part", "IPN", "Name", "Category", "Quantity", "Unit value", "Value", "Price source" ])
    valuation.rows.each do |row|
      csv << CSV.generate_line([
        csv_text(row.part.reference),
        csv_text(row.part.ipn),
        csv_text(row.part.name),
        csv_text(row.part.category&.name),
        row.quantity,
        row.unit_value&.to_s("F"),
        row.value.to_d.round(2).to_s("F"),
        row.source
      ])
    end
    csv
  end
end
