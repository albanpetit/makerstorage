import * as zxing from '@zxing/library'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { bitmapToBase64, renderLabelBitmap } from './label-bitmap'
import { qrMatrix, QR_QUIET_MODULES } from './labels'

// The tests run in Node: a canvas good enough for the label, painting the
// rectangles it fills (the QR code) and recording the text it writes.
class FakeContext {
  fillStyle = '#fff'
  font = '10px sans-serif'
  textBaseline = 'alphabetic'
  readonly texts: string[] = []
  readonly pixels: Uint8ClampedArray

  constructor(readonly width: number, readonly height: number) {
    this.pixels = new Uint8ClampedArray(width * height * 4).fill(255)
  }

  fillRect(x: number, y: number, w: number, h: number) {
    const value = this.fillStyle === '#000' ? 0 : 255
    for (let row = Math.max(0, y); row < Math.min(this.height, y + h); row++) {
      for (let col = Math.max(0, x); col < Math.min(this.width, x + w); col++) {
        const i = (row * this.width + col) * 4
        this.pixels[i] = this.pixels[i + 1] = this.pixels[i + 2] = value
      }
    }
  }

  // Half the font size per character, like a monospace font.
  measureText(text: string) {
    return { width: text.length * parseFloat(this.font.replace(/^700 /, '')) * 0.5 }
  }

  fillText(text: string) {
    this.texts.push(text)
  }

  getImageData() {
    return { data: this.pixels }
  }
}

let contexts: FakeContext[] = []

beforeEach(() => {
  contexts = []
  vi.stubGlobal('window', { location: { origin: 'https://stock.example' } })
  vi.stubGlobal('document', {
    createElement: () => {
      const canvas = {
        width: 0,
        height: 0,
        getContext: () => {
          const ctx = new FakeContext(canvas.width, canvas.height)
          contexts.push(ctx)
          return ctx
        },
      }
      return canvas
    },
  })
})

afterEach(() => {
  vi.unstubAllGlobals()
})

const item = { code: 'MS-001', title: 'MS-001', lines: ['10k resistor', 'Drawer A'] }
const bit = (bitmap: Uint8Array, rowBytes: number, x: number, y: number) => (bitmap[y * rowBytes + (x >> 3)] >> (7 - (x & 7))) & 1

describe('renderLabelBitmap', () => {
  it('packs rows of ceil(width / 8) bytes', () => {
    const bitmap = renderLabelBitmap(zxing, item, { width: 300, height: 120, dots_per_mm: 8 })
    expect(bitmap.length).toBe(Math.ceil(300 / 8) * 120)
  })

  it('draws the QR code on the left with whole dots per module, and the text beside it', () => {
    const geometry = { width: 496, height: 232, dots_per_mm: 8 } // 62 × 29 mm at 203 dpi
    const bitmap = renderLabelBitmap(zxing, item, geometry)
    const rowBytes = Math.ceil(geometry.width / 8)

    const modules = qrMatrix(zxing, 'https://stock.example/scan?code=MS-001').getWidth()
    const box = modules + QR_QUIET_MODULES * 2
    const padding = Math.round(1.5 * geometry.dots_per_mm)
    const scale = Math.floor(Math.min(geometry.height - padding * 2, geometry.width * 0.5) / box)
    const top = Math.round((geometry.height - box * scale) / 2)
    const origin = (n: number) => padding + (QR_QUIET_MODULES + n) * scale

    // The three finder patterns' corners are dark, the quiet zone light.
    expect(bit(bitmap, rowBytes, origin(0), top + QR_QUIET_MODULES * scale)).toBe(1)
    expect(bit(bitmap, rowBytes, origin(modules - 1), top + QR_QUIET_MODULES * scale)).toBe(1)
    expect(bit(bitmap, rowBytes, origin(0), top + (QR_QUIET_MODULES + modules - 1) * scale)).toBe(1)
    expect(bit(bitmap, rowBytes, padding, top)).toBe(0)
    expect(contexts[0].texts).toEqual(['MS-001', '10k resistor', 'Drawer A'])
  })

  it('prints the code under the lines when the title is something else', () => {
    renderLabelBitmap(zxing, { code: 'part:7', title: '10k resistor', lines: [] }, { width: 496, height: 232, dots_per_mm: 8 })
    expect(contexts[0].texts).toEqual(['10k resistor', 'part:7'])
  })

  it('drops the lines that do not fit the label height', () => {
    const lines = Array.from({ length: 20 }, (_, i) => `line ${i}`)
    renderLabelBitmap(zxing, { ...item, lines }, { width: 496, height: 232, dots_per_mm: 8 })
    const texts = contexts[0].texts
    expect(texts[0]).toBe('MS-001')
    expect(texts.length).toBeLessThan(lines.length)
  })

  it('draws labels longer than wide in landscape, then turns them', () => {
    const geometry = { width: 232, height: 496, dots_per_mm: 8 }
    const bitmap = renderLabelBitmap(zxing, item, geometry)
    expect(contexts[0].width).toBe(496)
    expect(contexts[0].height).toBe(232)
    expect(bitmap.length).toBe(Math.ceil(232 / 8) * 496)

    // A dark pixel at (x, y) of the drawing lands at (height - 1 - y, x).
    const ctx = contexts[0]
    const rowBytes = Math.ceil(geometry.width / 8)
    for (let y = 0; y < ctx.height; y += 7) {
      for (let x = 0; x < ctx.width; x += 7) {
        const dark = ctx.pixels[(y * ctx.width + x) * 4] === 0 ? 1 : 0
        expect(bit(bitmap, rowBytes, ctx.height - 1 - y, x)).toBe(dark)
      }
    }
  })

  it('skips the text when there is no room beside the code', () => {
    renderLabelBitmap(zxing, item, { width: 64, height: 48, dots_per_mm: 8 })
    expect(contexts[0].texts).toEqual([])
  })
})

describe('bitmapToBase64', () => {
  it('encodes the bytes, large bitmaps included', () => {
    expect(bitmapToBase64(new Uint8Array([0xff, 0x00, 0x80]))).toBe('/wCA')
    const large = new Uint8Array(100_000).fill(0xaa)
    expect(atob(bitmapToBase64(large)).length).toBe(100_000)
  })
})
