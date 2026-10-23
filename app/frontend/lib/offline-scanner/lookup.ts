// The Scanner page's lookup, answered from the snapshot kept on the device
// (OfflineScanSnapshot) when the server can't be reached. Mirrors
// ScansController#lookup and ScanCode: results have the same shape as the
// page's `result` prop, so the page renders them the same way.
import { movementReference, parseSupplierLabel, type SupplierLabel } from './supplier-label'

export type { SupplierLabel }

export interface ScanLocationOption {
  id: number
  name: string
  code: string | null
  location_type: string
  quantity: number
}

export interface ScannedPart {
  id: number
  reference: string
  name: string
  category: { name: string; color: string | null } | null
  total_quantity: number
  stock_status: 'out_of_stock' | 'low_stock' | 'sufficient'
  locations: ScanLocationOption[]
}

export interface ScannedZone {
  id: number
  name: string
  full_path: string
  location_type: string
  parts_count: number
  total_quantity: number
  children_count: number
  // Stocked parts held directly in the zone, largest quantity first (capped).
  contents: Array<{ id: number; reference: string; name: string; quantity: number }>
  // The stocktake already counting this zone, if any (never known offline).
  stocktake: { id: number; reference: string | null } | null
}

export interface SupplierLabelResult {
  kind: 'supplier_label'
  label: SupplierLabel
  // Stamped on the receipt movement (e.g. "DigiKey 84512345").
  reference: string
  // The inventory part the label matched, if any.
  part: ScannedPart | null
  // The same bag was already received (same part, order and quantity).
  previous_receipt: { created_at: string; quantity: number; location_name: string } | null
  open_orders: Array<{ id: number; reference: string | null; quantity: number }>
}

export type ScanResult =
  | { kind: 'part'; part: ScannedPart }
  | { kind: 'location'; location: ScannedZone }
  | SupplierLabelResult
  | { kind: 'unknown' }

export interface OfflinePart {
  id: number
  reference: string
  name: string
  ipn: string | null
  barcode: string | null
  sku: string | null
  mpn: string | null
  supplier_skus: string[]
  category: { name: string; color: string | null } | null
  min_stock_threshold: number
  // [zone id, quantity] pairs.
  stock: Array<[number, number]>
}

export interface OfflineLocation {
  id: number
  name: string
  full_path: string
  code: string | null
  location_type: string
  parent_id: number | null
}

export interface OfflineSnapshot {
  organization_id: number
  generated_at: string
  allow_negative_stock: boolean
  parts: OfflinePart[]
  locations: OfflineLocation[]
  open_orders: Array<{ part_id: number; id: number; reference: string | null; quantity: number }>
  label_receipts: Array<{ part_id: number; reference: string; quantity: number; created_at: string; location_name: string }>
}

/** A count or bag receipt recorded offline, waiting to be sent (OfflineScanSync). */
export interface PendingScan {
  id: string
  organization_id: number
  kind: 'count' | 'receipt'
  part_id: number
  storage_location_id: number
  // A signed delta for a count, the bag's quantity for a receipt.
  quantity: number
  reference: string | null
  scanned_at: string
  // Shown in the page's list of scans waiting to be sent (not sent to the server).
  part_reference: string
  location_name: string
  // Why the server refused it; such a scan stays until it's discarded.
  error?: string | null
}

const PART_CODE = /^part:(\d+)$/i
const ZONE_CODE = /^zone:(\d+)$/i
const ZONE_CONTENTS_LIMIT = 50

/** ScanCode.normalize: a label's `https://host/scan?code=…` link read as its code. */
export function normalizeCode(raw: string): string {
  const code = raw.trim()
  if (!/^https?:\/\//i.test(code)) return code
  try {
    const url = new URL(code)
    if (!url.pathname.replace(/\/$/, '').endsWith('/scan')) return code
    return url.searchParams.get('code')?.trim() || code
  } catch {
    return code
  }
}

const same = (value: string | null | undefined, code: string) => !!value && value.toLowerCase() === code

/**
 * The stock as the server will see it once the pending scans are sent: the
 * snapshot's quantities plus every scan not refused yet.
 */
export function stockWithPending(snapshot: OfflineSnapshot, pending: PendingScan[]) {
  const stock = new Map<number, Map<number, number>>()
  for (const part of snapshot.parts) stock.set(part.id, new Map(part.stock))
  for (const scan of pending) {
    if (scan.error || scan.organization_id !== snapshot.organization_id) continue
    const zones = stock.get(scan.part_id) ?? new Map<number, number>()
    zones.set(scan.storage_location_id, (zones.get(scan.storage_location_id) ?? 0) + scan.quantity)
    stock.set(scan.part_id, zones)
  }
  return stock
}

export class OfflineLookup {
  private readonly stock: Map<number, Map<number, number>>
  private readonly locationsById: Map<number, OfflineLocation>

  constructor(private readonly snapshot: OfflineSnapshot, private readonly pending: PendingScan[]) {
    this.stock = stockWithPending(snapshot, pending)
    this.locationsById = new Map(snapshot.locations.map((location) => [location.id, location]))
  }

  lookup(code: string): ScanResult {
    const label = parseSupplierLabel(code)
    if (label) return this.labelResult(label)

    const part = this.findPart(code)
    if (part) return { kind: 'part', part: this.serializePart(part) }

    const location = this.findLocation(code)
    if (location) return { kind: 'location', location: this.serializeLocation(location) }

    return { kind: 'unknown' }
  }

  partById(id: number): ScannedPart | null {
    const part = this.snapshot.parts.find((candidate) => candidate.id === id)
    return part ? this.serializePart(part) : null
  }

  // IPNs first: unique per organization and what labels print.
  private findPart(code: string): OfflinePart | undefined {
    const parts = this.snapshot.parts
    const match = code.match(PART_CODE)
    if (match) return parts.find((part) => part.id === Number(match[1]))

    const lower = code.toLowerCase()
    return parts.find((part) => same(part.ipn, lower))
      ?? parts.find((part) => same(part.barcode, lower) || same(part.sku, lower) || same(part.mpn, lower))
  }

  private findLocation(code: string): OfflineLocation | undefined {
    const match = code.match(ZONE_CODE)
    if (match) return this.locationsById.get(Number(match[1]))

    const lower = code.toLowerCase()
    return this.snapshot.locations.find((location) => same(location.code, lower))
  }

  // Customer part number → IPN, then the distributor's part number, then MPN.
  private findLabelPart(label: SupplierLabel): OfflinePart | undefined {
    const parts = this.snapshot.parts
    if (label.customer_part_number) {
      const cpn = label.customer_part_number.toLowerCase()
      const part = parts.find((candidate) => same(candidate.ipn, cpn))
      if (part) return part
    }
    if (label.supplier_sku) {
      const sku = label.supplier_sku.toLowerCase()
      const part = parts.find((candidate) => same(candidate.sku, sku))
        ?? parts.find((candidate) => candidate.supplier_skus.some((supplierSku) => same(supplierSku, sku)))
      if (part) return part
    }
    if (label.mpn) {
      const mpn = label.mpn.toLowerCase()
      return parts.find((candidate) => same(candidate.mpn, mpn))
    }
    return undefined
  }

  private labelResult(label: SupplierLabel): SupplierLabelResult {
    const part = this.findLabelPart(label)
    const reference = movementReference(label)
    return {
      kind: 'supplier_label',
      label,
      reference,
      part: part ? this.serializePart(part) : null,
      previous_receipt: part ? this.previousReceipt(part, label, reference) : null,
      open_orders: part
        ? this.snapshot.open_orders.filter((order) => order.part_id === part.id).map(({ id, reference: orderReference, quantity }) => ({ id, reference: orderReference, quantity }))
        : [],
    }
  }

  // The last receipt of this same bag, received online or queued here.
  private previousReceipt(part: OfflinePart, label: SupplierLabel, reference: string) {
    if (!label.order_number) return null

    const queued = this.pending
      .filter((scan) => scan.kind === 'receipt' && !scan.error && scan.organization_id === this.snapshot.organization_id)
      .map((scan) => ({
        part_id: scan.part_id,
        reference: scan.reference ?? '',
        quantity: scan.quantity,
        created_at: scan.scanned_at,
        location_name: this.locationsById.get(scan.storage_location_id)?.name ?? '',
      }))
    const receipt = [...queued, ...this.snapshot.label_receipts]
      .filter((candidate) => candidate.part_id === part.id && candidate.reference === reference)
      .filter((candidate) => label.quantity === null || candidate.quantity === label.quantity)
      .sort((a, b) => b.created_at.localeCompare(a.created_at))[0]
    return receipt ? { created_at: receipt.created_at, quantity: receipt.quantity, location_name: receipt.location_name } : null
  }

  private serializePart(part: OfflinePart): ScannedPart {
    const zones = [...(this.stock.get(part.id) ?? new Map<number, number>()).entries()]
      .filter(([locationId, quantity]) => quantity !== 0 && this.locationsById.has(locationId))
      .sort((a, b) => b[1] - a[1])
    const total = zones.reduce((sum, [, quantity]) => sum + quantity, 0)
    let locations = zones.map(([locationId, quantity]) => this.locationOption(this.locationsById.get(locationId)!, quantity))
    // A part never stored can still receive stock: offer every zone.
    if (locations.length === 0) locations = this.snapshot.locations.map((location) => this.locationOption(location, 0))

    return {
      id: part.id,
      reference: part.reference,
      name: part.name,
      category: part.category,
      total_quantity: total,
      stock_status: total === 0 ? 'out_of_stock' : total < part.min_stock_threshold ? 'low_stock' : 'sufficient',
      locations,
    }
  }

  private locationOption(location: OfflineLocation, quantity: number): ScanLocationOption {
    return { id: location.id, name: location.full_path, code: location.code, location_type: location.location_type, quantity }
  }

  private serializeLocation(location: OfflineLocation): ScannedZone {
    const held: Array<{ part: OfflinePart; quantity: number }> = []
    let total = 0
    for (const part of this.snapshot.parts) {
      const quantity = this.stock.get(part.id)?.get(location.id) ?? 0
      total += quantity
      if (quantity > 0) held.push({ part, quantity })
    }
    held.sort((a, b) => b.quantity - a.quantity)

    return {
      id: location.id,
      name: location.name,
      full_path: location.full_path,
      location_type: location.location_type,
      parts_count: held.length,
      total_quantity: total,
      children_count: this.snapshot.locations.filter((child) => child.parent_id === location.id).length,
      contents: held.slice(0, ZONE_CONTENTS_LIMIT).map(({ part, quantity }) => ({ id: part.id, reference: part.reference, name: part.name, quantity })),
      stocktake: null,
    }
  }
}
