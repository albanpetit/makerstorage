import type { InertiaFormProps } from '@inertiajs/react'

import type { LabelGeometry } from '@/lib/label-bitmap'

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
  notify_low_stock: boolean
  notify_late_orders: boolean
  notify_overdue_loans: boolean
  notification_frequency: NotificationFrequency
  stock_reservations_enabled: boolean
  default_loan_days: number
  mouser_api_key_present: boolean
  mouser_order_api_key_present: boolean
  digikey_configured: boolean
  digikey_account_connected: boolean
  lcsc_enabled: boolean
  github_token_present: boolean
  parts_count: number
  ipn_preview: IpnPreview
  free_bags_count: number
  free_bag_codes: string[]
}

export interface MergeTarget {
  id: number
  name: string
}

export interface KicadSettings {
  enabled: boolean
  token_created_at: string | null
  token_last_used_at: string | null
  root_url: string
  listed_parts_count: number
  parts_without_symbol_count: number
}

export type LabelPrinterProtocol = 'brother_ql' | 'zpl'

// What a printer's settings row and its test print need.
export interface LabelPrinterSettings extends LabelGeometry {
  id: number
  name: string
  protocol: LabelPrinterProtocol
  host: string
  port: number
  media: string | null
  width_mm: number | null
  length_mm: number | null
  dpi: number | null
  // "62 × 29 mm"
  size: string
}

// A Brother DK roll (LabelPrinting::BrotherQl::MEDIA).
export interface LabelPrinterMedia {
  id: string
  name: string
  continuous: boolean
}

export interface SettingsPageProps {
  organization: OrganizationSettings
  merge_targets: MergeTarget[]
  label_printers: LabelPrinterSettings[]
  label_printer_media: LabelPrinterMedia[]
  network_printing_enabled: boolean
  currencies: string[]
  ipn_separators: string[]
  timezones: string[]
  email_notifications_available: boolean
  kicad: KicadSettings
}

export type NotificationFrequency = 'daily' | 'weekly'

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
    default_loan_days: number
  }
}

export interface NotificationsFormData {
  organization: {
    notify_low_stock: boolean
    notify_late_orders: boolean
    notify_overdue_loans: boolean
    notification_frequency: NotificationFrequency
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
    github_token: string
    remove_github_token: boolean
  }
}

export type GeneralForm = InertiaFormProps<GeneralFormData>
export type IpnForm = InertiaFormProps<IpnFormData>
export type InventoryForm = InertiaFormProps<InventoryFormData>
export type NotificationsForm = InertiaFormProps<NotificationsFormData>
export type IntegrationsForm = InertiaFormProps<IntegrationsFormData>
