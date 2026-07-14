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
      created = ensure_catalog_suppliers
      notice = "Settings updated successfully."
      notice += " Added #{created.to_sentence} to your suppliers." if created.any?
      redirect_to settings_path, notice: notice
    else
      redirect_to settings_path, inertia: { errors: inertia_errors(current_organization, as: :organization) }, alert: "Failed to update settings."
    end
  end

  # Renumber every existing part with the org's current IPN format. Overwrites
  # the references parts already have, so the UI gates this behind a destructive
  # confirmation.
  def reassign_ipns
    if current_organization.ipn_generation_mode == "manual"
      return redirect_to settings_path, alert: "Turn on an automatic numbering mode before reassigning IPNs."
    end

    count = current_organization.reassign_ipns!
    redirect_to settings_path, notice: "Reassigned IPNs to #{count} #{'part'.pluralize(count)}."
  end

  private

  # Make sure each configured catalog integration has its supplier record so a
  # lookup can auto-fill that supplier's price. Returns the names of any newly
  # created suppliers, so the user can be told a supplier was set up for them.
  def ensure_catalog_suppliers
    providers = []
    providers << "mouser" if current_organization.mouser_api_key.present?
    providers << "digikey" if current_organization.digikey_configured?

    providers.filter_map do |provider|
      _supplier, created = Supplier.ensure_catalog_provider(current_organization, provider)
      Supplier::CATALOG_PROVIDER_DEFAULTS.dig(provider, :name) if created
    end
  end

  def organization_params
    permitted = params.require(:organization).permit(
      :name, :email, :phone, :website, :logo,
      :address_line1, :address_line2, :city, :postcode, :country,
      :currency, :timezone,
      :ipn_generation_mode, :ipn_charset,
      :ipn_prefix, :ipn_separator, :ipn_digits, :ipn_use_category_code, :ipn_next_sequence,
      :default_low_stock_threshold, :allow_negative_stock,
      :mouser_api_key, :remove_mouser_api_key,
      :digikey_client_id, :digikey_client_secret, :remove_digikey
    )

    normalize_mouser_api_key(permitted)
    normalize_digikey_credentials(permitted)
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

  # DigiKey's Client ID + Secret are write-only as a pair: a blank field leaves
  # the stored value untouched, an explicit remove flag clears both, and a new
  # value replaces it.
  def normalize_digikey_credentials(permitted)
    if ActiveModel::Type::Boolean.new.cast(permitted.delete(:remove_digikey))
      permitted[:digikey_client_id] = nil
      permitted[:digikey_client_secret] = nil
      return
    end

    %i[digikey_client_id digikey_client_secret].each do |key|
      if permitted[key].blank?
        permitted.delete(key)
      else
        permitted[key] = permitted[key].strip
      end
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
      digikey_configured: org.digikey_configured?,
      parts_count: org.total_parts_count,
      ipn_preview: org.ipn_preview(category_code: org.ipn_use_category_code ? "RES" : nil)
    }
  end
end
