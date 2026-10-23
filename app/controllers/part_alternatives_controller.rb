# frozen_string_literal: true

# Parts that can stand in for a part (PartAlternative), linked and unlinked
# from the part sheet. The link reads both ways, so it shows on both parts.
class PartAlternativesController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_writer, except: :index
  before_action :set_part

  # The parts the "Link an alternative" picker offers (JSON): every other part
  # not linked yet, obsolete ones left out.
  def index
    linked = @part.alternative_links.pluck(:part_id, :alternative_part_id).flatten
    parts = current_organization.parts.alphabetical
      .where.not(id: [ @part.id, *linked ])
      .where.not(status: "obsolete")
      .pluck(:id, :name, :mpn, :sku, :ipn, :value)

    render json: {
      parts: parts.map do |id, name, mpn, sku, ipn, value|
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
