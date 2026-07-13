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
    current_organization.logo.purge if ActiveModel::Type::Boolean.new.cast(params.dig(:organization, :remove_logo))

    if current_organization.update(organization_params)
      redirect_to settings_path, notice: "Settings updated successfully."
    else
      redirect_to settings_path, inertia: { errors: inertia_errors(current_organization, as: :organization) }, alert: "Failed to update settings."
    end
  end

  private

  def organization_params
    permitted = params.require(:organization).permit(
      :name, :email, :phone, :website, :logo,
      :address_line1, :address_line2, :city, :postcode, :country,
      :currency, :timezone,
      :ipn_generation_mode, :ipn_charset,
      :ipn_prefix, :ipn_separator, :ipn_digits, :ipn_use_category_code, :ipn_next_sequence,
      :default_low_stock_threshold, :allow_negative_stock,
      :mouser_api_key, :remove_mouser_api_key
    )

    normalize_mouser_api_key(permitted)
    permitted
  end

  # The Mouser key field is write-only: a blank submit leaves the stored key
  # untouched, an explicit remove flag clears it, and a new value replaces it.
  def normalize_mouser_api_key(permitted)
    remove = ActiveModel::Type::Boolean.new.cast(permitted.delete(:remove_mouser_api_key))

    if remove
      permitted[:mouser_api_key] = nil
    elsif permitted[:mouser_api_key].blank?
      permitted.delete(:mouser_api_key)
    else
      permitted[:mouser_api_key] = permitted[:mouser_api_key].strip
    end
  end

  def serialize_organization_settings
    org = current_organization

    {
      id: org.id,
      logo_url: org.logo.attached? ? rails_blob_path(org.logo, only_path: true) : nil,
      name: org.name, email: org.email, phone: org.phone, website: org.website,
      address_line1: org.address_line1, address_line2: org.address_line2,
      city: org.city, postcode: org.postcode, country: org.country,
      currency: org.currency, timezone: org.timezone,
      ipn_generation_mode: org.ipn_generation_mode, ipn_charset: org.ipn_charset,
      ipn_prefix: org.ipn_prefix, ipn_separator: org.ipn_separator, ipn_digits: org.ipn_digits,
      ipn_use_category_code: org.ipn_use_category_code, ipn_next_sequence: org.ipn_next_sequence,
      default_low_stock_threshold: org.default_low_stock_threshold, allow_negative_stock: org.allow_negative_stock,
      mouser_api_key_present: org.mouser_api_key.present?,
      ipn_preview: org.ipn_preview(category_code: org.ipn_use_category_code ? "RES" : nil)
    }
  end
end
