import type { StorageLocationOption } from '@/components/storage-location-select'
import { ORDER_STATUS_META } from '@/pages/orders/helpers'

// Prop shapes for the order page (OrdersController#show).

export interface Allocation {
  id: number
  storage_location_id: number
  storage_location_path: string
  quantity: number
}

export interface OrderLine {
  id: number
  quantity: number
  unit_price: number | null
  subtotal: number | null
  allocated_quantity: number
  allocations: Allocation[]
  part: { id: number; reference: string; name: string; unit: string }
}

export interface Order {
  id: number
  reference: string | null
  status: keyof typeof ORDER_STATUS_META
  editable: boolean
  supplier: { id: number; name: string }
  ordered_at: string | null
  expected_delivery: string | null
  notes: string | null
  total_amount: number
  lines: OrderLine[]
}

export interface SupplierOption {
  id: number
  name: string
}

export interface PartOption {
  id: number
  reference: string
  name: string
  mpn: string | null
  sku: string | null
}

export interface CategoryOption {
  id: number
  name: string
}

export interface ProjectOption {
  id: number
  name: string
  reference: string | null
  line_count: number
}

export interface OrderShowProps {
  order: Order
  suppliers: SupplierOption[]
  /** Deferred: undefined until the page has loaded it. */
  parts?: PartOption[]
  categories: CategoryOption[]
  catalog_enabled: boolean
  projects: ProjectOption[]
  mouser_cart_enabled: boolean
  storage_locations: StorageLocationOption[]
}
