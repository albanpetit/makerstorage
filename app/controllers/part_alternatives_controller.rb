# frozen_string_literal: true

# Parts that can stand in for a part (PartAlternative), linked and unlinked
# from the part sheet. The link reads both ways, so it shows on both parts.
class PartAlternativesController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, except: :index
  before_action :set_part

  # Most parts one picker search returns.
  PICKER_LIMIT = 20

  # The parts the "Link an alternative" picker offers (JSON), searched on the
  # server (Part.search, plus the IPN) so the organization's whole inventory
  # never goes to the browser: other parts not linked yet, obsolete ones left
  # out, the first PICKER_LIMIT by name.
  def index
    linked = @part.alternative_links.pluck(:part_id, :alternative_part_id).flatten
    parts = current_organization.parts.alphabetical
      .where.not(id: [ @part.id, *linked ])
      .where.not(status: "obsolete")
    if (query = params[:q].to_s.strip).present?
      parts = parts.search(query).or(parts.where("parts.ipn LIKE ? ESCAPE '\\'", "%#{Part.sanitize_sql_like(query)}%"))
    end

    render json: {
      parts: parts.limit(PICKER_LIMIT).pluck(:id, :name, :mpn, :sku, :ipn, :value).map do |id, name, mpn, sku, ipn, value|
        { id: id, name: name, mpn: mpn, sku: sku, ipn: ipn, value: value }
      end
    }
  end

  def create
    other = current_organization.parts.find(params.require(:alternative_part_id))
    PartAlternative.link!(@part, other, note: params[:note].to_s)
    redirect_back_or_to parts_path, notice: t("flash.part_alternatives.linked", name: other.name)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_or_to parts_path, alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    link = find_link
    other = current_organization.parts.find(link.other_id(@part.id))
    link.destroy!
    redirect_back_or_to parts_path, notice: t("flash.part_alternatives.unlinked", name: other.name)
  end

  private

  def set_part
    @part = current_organization.parts.find(params[:part_id])
  end

  def find_link
    @part.alternative_links.find(params[:id])
  end
end
