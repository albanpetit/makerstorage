# frozen_string_literal: true

class SettingsController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_admin

  def show
    render inertia: "settings/index", props: {
      organization: serialize_organization_settings,
      currencies: Organization::CURRENCIES,
      ipn_separators: Organization::IPN_SEPARATORS,
      timezones: ActiveSupport::TimeZone::MAPPING.values.sort.uniq
    }
  end

  def update
    if current_organization.update(organization_params)
      redirect_to settings_path, notice: "Settings updated successfully."
    else
      redirect_to settings_path, inertia: { errors: current_organization.errors }, alert: "Failed to update settings."
    end
  end

  private

  def organization_params
    params.require(:organization).permit(
      :name, :email, :phone, :website,
      :address_line1, :address_line2, :city, :postcode, :country,
      :currency, :timezone,
      :ipn_generation_mode, :ipn_charset,
      :ipn_prefix, :ipn_separator, :ipn_digits, :ipn_use_category_code, :ipn_next_sequence,
      :default_low_stock_threshold, :allow_negative_stock
    )
  end

  def serialize_organization_settings
    org = current_organization

    {
      name: org.name, email: org.email, phone: org.phone, website: org.website,
      address_line1: org.address_line1, address_line2: org.address_line2,
      city: org.city, postcode: org.postcode, country: org.country,
      currency: org.currency, timezone: org.timezone,
      ipn_generation_mode: org.ipn_generation_mode, ipn_charset: org.ipn_charset,
      ipn_prefix: org.ipn_prefix, ipn_separator: org.ipn_separator, ipn_digits: org.ipn_digits,
      ipn_use_category_code: org.ipn_use_category_code, ipn_next_sequence: org.ipn_next_sequence,
      default_low_stock_threshold: org.default_low_stock_threshold, allow_negative_stock: org.allow_negative_stock,
      ipn_preview: org.ipn_preview(category_code: org.ipn_use_category_code ? "RES" : nil)
    }
  end
end
