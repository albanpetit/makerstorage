import { describe, expect, it } from 'vitest'

import { normalizeCode, OfflineLookup, stockWithPending, type OfflineSnapshot, type PendingScan } from './lookup'

// Mirrors test/controllers/scans_controller_test.rb: offline answers must
// match what ScansController#lookup sends.
const GS = '\u001D'
const RS = '\u001E'
const EOT = '\u0004'
const ecia = (...fields: string[]) => `[)>${RS}06${GS}${fields.join(GS)}${RS}${EOT}`

const part = (overrides: Partial<OfflineSnapshot['parts'][number]>) => ({
  id: 1, reference: 'MS-001', name: 'Resistor', ipn: null, barcode: null, sku: null, mpn: null,
  supplier_skus: [], category: null, min_stock_threshold: 0, stock: [], ...overrides,
})

function snapshot(overrides: Partial<OfflineSnapshot> = {}): OfflineSnapshot {
  return {
    organization_id: 10,
    generated_at: '2026-11-20T10:00:00Z',
    allow_negative_stock: false,
    parts: [
      part({ id: 1, reference: 'MS-001', name: '10k resistor', ipn: 'MS-001', mpn: 'RC0603', min_stock_threshold: 50, stock: [[100, 30], [101, 5]] }),
      part({ id: 2, reference: 'MS-002', name: 'Shift register', ipn: 'MS-002', sku: 'S-595', mpn: 'SN74HC595N', supplier_skus: ['296-1395-5-ND'], stock: [[100, 12]] }),
      part({ id: 3, reference: 'MS-003', name: 'Never stored', barcode: '4006381333931' }),
    ],
    locations: [
      { id: 100, name: 'Drawer A', full_path: 'Cabinet › Drawer A', code: 'A1', location_type: 'drawer', parent_id: 99 },
      { id: 101, name: 'Drawer B', full_path: 'Cabinet › Drawer B', code: null, location_type: 'drawer', parent_id: 99 },
      { id: 99, name: 'Cabinet', full_path: 'Cabinet', code: 'CAB', location_type: 'cabinet', parent_id: null },
    ],
    open_orders: [ { part_id: 2, id: 500, reference: 'PO-1', quantity: 25 } ],
    label_receipts: [
      { part_id: 2, reference: 'DigiKey 84512345', quantity: 25, created_at: '2026-11-01T09:00:00Z', location_name: 'Drawer A' },
    ],
    ...overrides,
  }
}

const pending = (overrides: Partial<PendingScan>): PendingScan => ({
  id: 'p1', organization_id: 10, kind: 'count', part_id: 1, storage_location_id: 100, quantity: 0,
  reference: null, scanned_at: '2026-11-20T11:00:00Z', part_reference: 'MS-001', location_name: 'Drawer A', ...overrides,
})

describe('normalizeCode', () => {
  it('keeps a plain code, trimmed', () => {
    expect(normalizeCode('  MS-001 ')).toBe('MS-001')
  })

  it("reads a label link's code, whatever host printed it", () => {
    expect(normalizeCode('https://other.example/scan?code=MS-001')).toBe('MS-001')
    expect(normalizeCode('http://stock.example/scan/?code=part%3A7')).toBe('part:7')
  })

  it('leaves other links alone', () => {
    expect(normalizeCode('https://stock.example/parts?code=MS-001')).toBe('https://stock.example/parts?code=MS-001')
    expect(normalizeCode('https://stock.example/scan')).toBe('https://stock.example/scan')
  })
})

describe('stockWithPending', () => {
  it('adds the scans not refused yet, for this organization only', () => {
    const stock = stockWithPending(snapshot(), [
      pending({ quantity: -4 }),
      pending({ id: 'p2', part_id: 3, storage_location_id: 101, quantity: 10, kind: 'receipt' }),
      pending({ id: 'p3', quantity: 100, error: 'Not enough stock' }),
      pending({ id: 'p4', quantity: 100, organization_id: 11 }),
    ])
    expect(stock.get(1)?.get(100)).toBe(26)
    expect(stock.get(3)?.get(101)).toBe(10)
  })
})

describe('OfflineLookup', () => {
  const lookup = (code: string, scans: PendingScan[] = []) => new OfflineLookup(snapshot(), scans).lookup(code)

  it('finds a part by IPN, case-insensitively, with its zones largest first', () => {
    expect(lookup('ms-001')).toEqual({
      kind: 'part',
      part: {
        id: 1, reference: 'MS-001', name: '10k resistor', category: null, total_quantity: 35, stock_status: 'low_stock',
        locations: [
          { id: 100, name: 'Cabinet › Drawer A', code: 'A1', location_type: 'drawer', quantity: 30 },
          { id: 101, name: 'Cabinet › Drawer B', code: null, location_type: 'drawer', quantity: 5 },
        ],
      },
    })
  })

  it('finds a part by record id, barcode, SKU or MPN', () => {
    expect(lookup('part:2')).toMatchObject({ kind: 'part', part: { id: 2 } })
    expect(lookup('4006381333931')).toMatchObject({ kind: 'part', part: { id: 3 } })
    expect(lookup('s-595')).toMatchObject({ kind: 'part', part: { id: 2 } })
    expect(lookup('RC0603')).toMatchObject({ kind: 'part', part: { id: 1 } })
  })

  it('offers every zone for a part never stored', () => {
    const result = lookup('part:3')
    expect(result).toMatchObject({ kind: 'part', part: { total_quantity: 0, stock_status: 'out_of_stock' } })
    if (result.kind !== 'part') throw new Error('expected a part')
    expect(result.part.locations.map((location) => location.id)).toEqual([100, 101, 99])
  })

  it('counts the scans waiting to be sent', () => {
    const result = lookup('MS-001', [pending({ quantity: 20 }), pending({ id: 'p2', storage_location_id: 101, quantity: -5 })])
    expect(result).toMatchObject({ kind: 'part', part: { total_quantity: 50, stock_status: 'sufficient' } })
    if (result.kind !== 'part') throw new Error('expected a part')
    expect(result.part.locations.map((location) => location.id)).toEqual([100])
  })

  it('finds a zone by code or id, with what it holds', () => {
    expect(lookup('a1')).toEqual({
      kind: 'location',
      location: {
        id: 100, name: 'Drawer A', full_path: 'Cabinet › Drawer A', location_type: 'drawer',
        parts_count: 2, total_quantity: 42, children_count: 0, stocktake: null,
        contents: [
          { id: 1, reference: 'MS-001', name: '10k resistor', quantity: 30 },
          { id: 2, reference: 'MS-002', name: 'Shift register', quantity: 12 },
        ],
      },
    })
    expect(lookup('zone:99')).toMatchObject({ kind: 'location', location: { id: 99, children_count: 2, parts_count: 0 } })
  })

  it('answers unknown for anything else', () => {
    expect(lookup('nope')).toEqual({ kind: 'unknown' })
    expect(lookup('zone:12345')).toEqual({ kind: 'unknown' })
  })

  it("matches a supplier label to the part by distributor part number, with its open orders and the bag's previous receipt", () => {
    const result = lookup(ecia('P296-1395-5-ND', '1PSN74HC595N', 'K', '1K84512345', 'Q25'))
    expect(result).toMatchObject({
      kind: 'supplier_label',
      reference: 'DigiKey 84512345',
      part: { id: 2 },
      previous_receipt: { created_at: '2026-11-01T09:00:00Z', quantity: 25, location_name: 'Drawer A' },
      open_orders: [ { id: 500, reference: 'PO-1', quantity: 25 } ],
    })
  })

  it('prefers the customer part number, and sees receipts queued on the device', () => {
    const scans = [pending({ kind: 'receipt', part_id: 1, quantity: 10, reference: 'DigiKey 777', scanned_at: '2026-11-20T12:00:00Z' })]
    const result = lookup(ecia('PMS-001', '30P296-1395-5-ND', '1PSN74HC595N', '1K777', 'Q10'), scans)
    expect(result).toMatchObject({
      kind: 'supplier_label',
      part: { id: 1 },
      previous_receipt: { created_at: '2026-11-20T12:00:00Z', quantity: 10, location_name: 'Drawer A' },
      open_orders: [],
    })
  })

  it('does not call another quantity of the same order the same bag', () => {
    const result = lookup(ecia('P296-1395-5-ND', '1K84512345', 'Q10'))
    expect(result).toMatchObject({ kind: 'supplier_label', part: { id: 2 }, previous_receipt: null })
  })

  it('reads a label for a part not in the inventory', () => {
    expect(lookup(ecia('P999-ND', '1PUNKNOWN', 'Q5'))).toMatchObject({ kind: 'supplier_label', part: null, previous_receipt: null, open_orders: [] })
  })

  it('looks a part up by id', () => {
    const offline = new OfflineLookup(snapshot(), [])
    expect(offline.partById(2)).toMatchObject({ id: 2, reference: 'MS-002' })
    expect(offline.partById(404)).toBeNull()
  })
})
