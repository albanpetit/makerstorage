import { LookupResult } from '@/components/supplier-lookup'

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
  website?: string | null
  catalog_provider?: string | null
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

// A supplier link as returned by the server (existing part-supplier row).
export interface PartSupplier {
  id: number
  supplier_id: number
  supplier_name: string
  supplier_sku: string | null
  unit_price: number | null
  lead_time_days: number | null
  url: string | null
  is_preferred: boolean
  notes: string | null
}

// A supplier row being edited in the form. Existing links carry their `id` (so
// the server updates rather than recreates); newly added ones leave it
// undefined.
export interface PendingSupplier {
  tempId: string
  id?: number
  supplier_id: string
  supplier_name: string
  supplier_sku: string
  unit_price: string
  lead_time_days: string
  url: string
  is_preferred: boolean
  notes: string
}

export type NewSupplier = Omit<PendingSupplier, 'tempId' | 'id' | 'supplier_name'>

// The flat, all-strings shape the part form fields bind to.
export interface PartFormData {
  name: string
  mpn: string
  sku: string
  barcode: string
  ipn: string
  manufacturer: string
  description: string
  value: string
  tolerance: string
  voltage_rating: string
  power_rating: string
  package_type: string
  category_id: string
  footprint_id: string
  unit_price: string
  min_stock_threshold: string
  target_stock: string
  status: string
  rohs_compliant: boolean
  storage_notes: string
  tag_ids: number[]
}

// The full part payload fetched from GET /parts/:id/edit (JSON).
export interface FullPart {
  id: number
  name: string
  mpn: string | null
  sku: string | null
  barcode: string | null
  ipn: string | null
  manufacturer: string | null
  description: string | null
  value: string | null
  tolerance: string | null
  voltage_rating: string | null
  power_rating: string | null
  package_type: string | null
  status: string
  unit_price: number | null
  min_stock_threshold: number
  target_stock: number | null
  rohs_compliant: boolean
  storage_notes: string | null
  category_id: number
  footprint_id: number | null
  tag_ids: number[]
  part_suppliers: PartSupplier[]
  thumbnail_url: string | null
}

export const EMPTY_SUPPLIER: NewSupplier = {
  supplier_id: '',
  supplier_sku: '',
  unit_price: '',
  lead_time_days: '',
  url: '',
  is_preferred: false,
  notes: '',
}

export const EMPTY_PART: PartFormData = {
  name: '',
  mpn: '',
  sku: '',
  barcode: '',
  ipn: '',
  manufacturer: '',
  description: '',
  value: '',
  tolerance: '',
  voltage_rating: '',
  power_rating: '',
  package_type: '',
  category_id: '',
  footprint_id: '',
  unit_price: '',
  min_stock_threshold: '0',
  target_stock: '',
  status: 'active',
  rohs_compliant: false,
  storage_notes: '',
  tag_ids: [],
}

// Maps a fetched part into the flat, all-strings shape the form fields use.
export function toFormPart(part: FullPart): PartFormData {
  return {
    name: part.name,
    mpn: part.mpn || '',
    sku: part.sku || '',
    barcode: part.barcode || '',
    ipn: part.ipn || '',
    manufacturer: part.manufacturer || '',
    description: part.description || '',
    value: part.value || '',
    tolerance: part.tolerance || '',
    voltage_rating: part.voltage_rating || '',
    power_rating: part.power_rating || '',
    package_type: part.package_type || '',
    category_id: part.category_id.toString(),
    footprint_id: part.footprint_id?.toString() || '',
    unit_price: part.unit_price?.toString() || '',
    min_stock_threshold: part.min_stock_threshold.toString(),
    target_stock: part.target_stock?.toString() || '',
    status: part.status,
    rohs_compliant: part.rohs_compliant,
    storage_notes: part.storage_notes || '',
    tag_ids: part.tag_ids,
  }
}

// Turns a (possibly dotted, nested) error key into a readable label, e.g.
// 'part.min_stock_threshold' -> 'Min Stock Threshold'.
export function fieldLabel(key: string): string {
  const name = key.includes('.') ? key.split('.').pop()! : key
  return name
    .replace(/_/g, ' ')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/\b\w/g, (char) => char.toUpperCase())
}

// The field patch to apply when a catalog lookup result is chosen. Only
// overwrites fields the result actually provides, leaving anything already
// entered intact.
export function lookupResultPatch(result: LookupResult, part: PartFormData): Partial<PartFormData> {
  return {
    name: result.name || part.name,
    mpn: result.mpn || part.mpn,
    manufacturer: result.manufacturer || part.manufacturer,
    description: result.description || part.description,
    value: result.value || part.value,
    package_type: result.package_type || part.package_type,
    tolerance: result.tolerance || part.tolerance,
    voltage_rating: result.voltage_rating || part.voltage_rating,
    power_rating: result.power_rating || part.power_rating,
    unit_price: result.unit_price || part.unit_price,
    rohs_compliant: result.rohs_compliant || part.rohs_compliant,
  }
}
