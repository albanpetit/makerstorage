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
}
