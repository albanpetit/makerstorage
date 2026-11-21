import * as zxing from '@zxing/library'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { isLabelFormatId, labelCodeForPart, labelCodeForZone, labelForPart, qrMatrix, scanUrl } from './labels'

const part = { id: 7, name: '10k resistor', ipn: null, mpn: null, sku: null, barcode: null, location_names: [] as string[] }

describe('labelCodeForPart', () => {
  it('prefers the IPN, then the barcode, then the SKU', () => {
    expect(labelCodeForPart({ ...part, ipn: 'MS-001', barcode: '123', sku: 'S1' })).toBe('MS-001')
    expect(labelCodeForPart({ ...part, barcode: '123', sku: 'S1' })).toBe('123')
    expect(labelCodeForPart({ ...part, sku: 'S1' })).toBe('S1')
  })

  it('falls back to the record id, never the MPN (several parts can share one)', () => {
    const withMpn = { ...part, mpn: 'RC0603' }
    expect(labelCodeForPart(withMpn)).toBe('part:7')
  })
})

describe('labelForPart', () => {
  it('titles the label with the IPN and lists the name, MPN and location', () => {
    expect(labelForPart({ ...part, ipn: 'MS-001', mpn: 'RC0603', location_names: ['Drawer A'] })).toEqual({
      code: 'MS-001',
      title: 'MS-001',
      lines: ['10k resistor', 'RC0603', 'Drawer A'],
    })
  })

  it('does not repeat the title in the lines', () => {
    const label = labelForPart({ ...part, mpn: 'RC0603', location_names: [] })
    expect(label.title).toBe('RC0603')
    expect(label.lines).toEqual(['10k resistor', '', '—'])
  })

  it('uses the name as the title when nothing else identifies the part', () => {
    expect(labelForPart(part)).toMatchObject({ code: 'part:7', title: '10k resistor', lines: ['', '', '—'] })
  })
})

describe('labelCodeForZone', () => {
  it('uses the zone code, else its id', () => {
    expect(labelCodeForZone({ id: 3, code: 'A1' })).toBe('A1')
    expect(labelCodeForZone({ id: 3, code: null })).toBe('zone:3')
  })
})

describe('isLabelFormatId', () => {
  it('accepts known formats only', () => {
    expect(isLabelFormatId('a4-3x8')).toBe(true)
    expect(isLabelFormatId('brother-62x29')).toBe(true)
    expect(isLabelFormatId('toString')).toBe(false)
    expect(isLabelFormatId(42)).toBe(false)
  })
})

describe('scanUrl', () => {
  beforeEach(() => {
    vi.stubGlobal('window', { location: { origin: 'https://stock.example' } })
  })
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('links to the scanner page with the code escaped', () => {
    expect(scanUrl('MS-001')).toBe('https://stock.example/scan?code=MS-001')
    expect(scanUrl('a b&c')).toBe('https://stock.example/scan?code=a%20b%26c')
  })
})

describe('qrMatrix', () => {
  it('encodes text that reads back the same', () => {
    const text = 'https://stock.example/scan?code=MS-001'
    const matrix = qrMatrix(zxing, text)
    const size = matrix.getWidth()
    expect(size).toBeGreaterThanOrEqual(21)

    // Draw it with a quiet zone and decode it again.
    const quiet = 4
    const side = size + quiet * 2
    const pixels = new Uint8ClampedArray(side * side).fill(255)
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) if (matrix.get(x, y) === 1) pixels[(y + quiet) * side + x + quiet] = 0
    }
    const source = new zxing.RGBLuminanceSource(pixels, side, side)
    const bitmap = new zxing.BinaryBitmap(new zxing.HybridBinarizer(source))
    expect(new zxing.QRCodeReader().decode(bitmap).getText()).toBe(text)
  })
})
