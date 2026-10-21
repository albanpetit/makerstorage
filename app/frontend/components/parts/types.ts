import type { AddPartPrefill, BagBox, BagOption } from '@/components/part-form/types'

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

// Shape of OptionListSerializers#serialize_storage_locations.
import type { StorageLocationOption } from '@/components/storage-location-select'
export type { StorageLocationOption }

export type SortKey = 'ref' | 'crit' | 'qtyDesc' | 'qtyAsc' | 'priceDesc'

// The list filters, as PartsIndexQuery applied them.
export interface PartListFilters {
  search: string
  category: number | null
  status: string[]
  package: string[]
  footprint: string[]
  supplier: string[]
  sort: SortKey
}

export interface FacetOption {
  value: string
  label: string
  count: number
}

export interface PartListFacets {
  categories: { id: number; name: string; count: number }[]
  status: FacetOption[]
  package: FacetOption[]
  footprint: FacetOption[]
  supplier: FacetOption[]
}

export interface PartListPagination {
  page: number
  page_count: number
  page_size: number
  total: number
}

export interface PartsIndexProps {
  // Only the current page of matching parts.
  parts: Part[]
  filters: PartListFilters
  pagination: PartListPagination
  facets: PartListFacets
  total_count: number
  total_units: number
  matching_ids: number[]
  // Loaded on demand by the CSV import dialog.
  part_identifiers?: { mpns: string[]; skus: string[] }
  categories: Category[]
  footprints: Footprint[]
  suppliers: Supplier[]
  tags: Tag[]
  storage_locations: StorageLocationOption[]
  supplier_lookup_enabled: boolean
  ipn_manual_entry: boolean
  bag_options: BagOption[] | null
  bag_boxes: BagBox[] | null
  open_add: boolean
  // Set when the add dialog opens from a scanned supplier label.
  add_prefill: AddPartPrefill | null
}
