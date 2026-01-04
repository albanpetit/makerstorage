# frozen_string_literal: true

class PartSuppliersController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :set_part
  before_action :set_part_supplier, only: %i[update destroy set_preferred]

  def create
    @part_supplier = @part.part_suppliers.build(part_supplier_params)

    if @part_supplier.save
      redirect_to edit_part_path(@part), notice: "Supplier added successfully."
    else
      redirect_to edit_part_path(@part), alert: @part_supplier.errors.full_messages.join(", ")
    end
  end

  def update
    if @part_supplier.update(part_supplier_params)
      redirect_to edit_part_path(@part), notice: "Supplier updated successfully."
    else
      redirect_to edit_part_path(@part), alert: @part_supplier.errors.full_messages.join(", ")
    end
  end

  def destroy
    @part_supplier.destroy
    redirect_to edit_part_path(@part), notice: "Supplier removed successfully."
  end

  def set_preferred
    # Mark this one as preferred (callback will unset others)
    @part_supplier.update!(is_preferred: true)
    redirect_to edit_part_path(@part), notice: "#{@part_supplier.supplier.name} set as preferred supplier."
  end

  private

  def set_part
    @part = current_organization.parts.find(params[:part_id])
  end

  def set_part_supplier
    @part_supplier = @part.part_suppliers.find(params[:id])
  end

  def part_supplier_params
    params.require(:part_supplier).permit(
      :supplier_id, :supplier_sku, :unit_price, :lead_time_days, :url, :is_preferred, :notes
    )
  end
end
