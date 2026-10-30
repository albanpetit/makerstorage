export type Flash = {
  notice?: string
  alert?: string
  // Set after PartsController#create, for printing the new part's label.
  created_part?: {
    id: number
    name: string
    ipn: string | null
    mpn: string | null
    sku: string | null
    barcode: string | null
    location_names: string[]
  }
}

export type SharedProps = {
  flash: Flash
  // UI language: the user's choice, else the browser's (Accept-Language), else English.
  locale: 'en' | 'fr'
  // The install's privacy policy and legal notice (PRIVACY_POLICY_URL, LEGAL_NOTICE_URL), if any.
  legal: { privacy_policy_url: string | null; legal_notice_url: string | null }
}
