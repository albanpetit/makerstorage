import type { InertiaFormProps } from '@inertiajs/react'

// Prop and form shapes for the Settings page (SettingsController#show).

export interface IpnPreview {
  next: string
  examples: string[]
}

export interface OrganizationSettings {
  id: number
  logo_url: string | null
  name: string
  email: string | null
  phone: string | null
  website: string | null
  address_line1: string | null
  address_line2: string | null
  city: string | null
  postcode: string | null
  country: string | null
  currency: string
  timezone: string
  ipn_generation_mode: IpnMode
  ipn_charset: string
  ipn_prefix: string
  ipn_separator: string
  ipn_digits: number
  ipn_use_category_code: boolean
  ipn_next_sequence: number
  default_low_stock_threshold: number
  allow_negative_stock: boolean
  stock_reservations_enabled: boolean
  mouser_api_key_present: boolean
  mouser_order_api_key_present: boolean
  digikey_configured: boolean
  digikey_account_connected: boolean
  parts_count: number
  ipn_preview: IpnPreview
  free_bags_count: number
  free_bag_codes: string[]
}

export interface SettingsPageProps {
  organization: OrganizationSettings
  currencies: string[]
  ipn_separators: string[]
  timezones: string[]
}

export type IpnMode = 'incremental' | 'random' | 'category_sequence' | 'manual' | 'box_bag'

export interface GeneralFormData {
  organization: {
    name: string
    email: string
    phone: string
    website: string
    logo: File | null
    remove_logo: boolean
    address_line1: string
    address_line2: string
    city: string
    postcode: string
    country: string
    currency: string
    timezone: string
  }
}

export interface IpnFormData {
  organization: {
    ipn_generation_mode: IpnMode
    ipn_charset: string
    ipn_prefix: string
    ipn_separator: string
    ipn_digits: number
    ipn_use_category_code: boolean
    ipn_next_sequence: number
  }
}

export interface InventoryFormData {
  organization: {
    default_low_stock_threshold: number
    allow_negative_stock: boolean
    stock_reservations_enabled: boolean
  }
}

export interface IntegrationsFormData {
  organization: {
    mouser_api_key: string
    remove_mouser_api_key: boolean
    mouser_order_api_key: string
    remove_mouser_order_api_key: boolean
    digikey_client_id: string
    digikey_client_secret: string
    remove_digikey: boolean
  }
}

export type GeneralForm = InertiaFormProps<GeneralFormData>
export type IpnForm = InertiaFormProps<IpnFormData>
export type InventoryForm = InertiaFormProps<InventoryFormData>
export type IntegrationsForm = InertiaFormProps<IntegrationsFormData>
