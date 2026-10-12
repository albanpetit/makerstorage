// Prop shapes for the Parts inventory page (PartsController#index), shared by
// the page and its pieces in this folder.

export interface Part {
  id: number
  name: string
  mpn: string | null
  sku: string | null
  ipn: string | null
  barcode: string | null
  manufacturer: string | null
  description: string | null
  value: string | null
  package_type: string | null
  status: 'active' | 'discontinued' | 'obsolete'
  tag_names: string[]
  thumbnail_url: string | null
  total_quantity: number
  min_stock_threshold: number
  unit_price: number | null
  location_names: string[]
  supplier_name: string | null
  category: {
    id: number
    name: string
    color: string | null
  } | null
  footprint: {
    id: number
    name: string
  } | null
}

export interface Category {
  id: number
  name: string
}

export interface Footprint {
  id: number
  name: string
  mounting_type: string | null
}

export interface Supplier {
  id: number
  name: string
}

export interface Tag {
  id: number
  name: string
  color: string | null
}

export interface StorageLocationOption {
  id: number
  name: string
}

export interface PartsIndexProps {
  parts: Part[]
  initial_query: string
  categories: Category[]
  footprints: Footprint[]
  suppliers: Supplier[]
  tags: Tag[]
  storage_locations: StorageLocationOption[]
  supplier_lookup_enabled: boolean
  ipn_manual_entry: boolean
  open_add: boolean
}
