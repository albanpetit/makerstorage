// Printable QR labels for parts and storage zones.
//
// Each QR code holds a link to the scanner page (`<origin>/scan?code=…`): a
// phone's own camera app opens the matching part or zone straight away, and
// the in-app scanner / hardware scanners resolve the same link (ScansController
// keeps only its `code`, whatever host printed it).

import { html, printDocument } from '@/lib/print-document'

export interface LabelItem {
  // What the scanner looks up (see labelCodeForPart / labelCodeForZone).
  code: string
  title: string
  lines: string[]
}

interface LabelFormat {
  name: string
  // Label size in millimetres.
  width: number
  height: number
  // Set for sheets holding several labels; roll printers get one label per page.
  sheet?: { cols: number; rows: number; pageWidth: number; pageHeight: number }
}

export const LABEL_FORMATS = {
  'a4-3x8': {
    name: 'A4 sheet · 24 labels (70 × 37 mm)',
    width: 70,
    height: 37,
    sheet: { cols: 3, rows: 8, pageWidth: 210, pageHeight: 297 },
  },
  'brother-62x29': { name: 'Brother DK-11209 · 62 × 29 mm', width: 62, height: 29 },
  'dymo-54x25': { name: 'Dymo 11352 · 54 × 25 mm', width: 54, height: 25 },
  'dymo-89x36': { name: 'Dymo 99012 · 89 × 36 mm', width: 89, height: 36 },
} satisfies Record<string, LabelFormat>

export type LabelFormatId = keyof typeof LABEL_FORMATS

export const DEFAULT_LABEL_FORMAT: LabelFormatId = 'a4-3x8'

export function isLabelFormatId(value: unknown): value is LabelFormatId {
  return typeof value === 'string' && Object.prototype.hasOwnProperty.call(LABEL_FORMATS, value)
}

// Parts are labelled with an identifier that is unique within the organization
// (IPN first, which the scanner also matches first), else their record id.
// MPNs are left out: several parts can share one.
export function labelCodeForPart(part: { id: number; ipn: string | null; barcode: string | null; sku: string | null }): string {
  return part.ipn || part.barcode || part.sku || `part:${part.id}`
}

export function labelCodeForZone(zone: { id: number; code: string | null }): string {
  return zone.code || `zone:${zone.id}`
}

export function scanUrl(code: string): string {
  return `${window.location.origin}/scan?code=${encodeURIComponent(code)}`
}

type ZxingLibrary = typeof import('@zxing/library')

// The QR symbol as an SVG path of dark modules, one unit per module, with a
// four-module quiet zone, the minimum the QR spec (and ZXing) expects.
function qrSvg(zxing: ZxingLibrary, text: string, sizeMm: number) {
  const { QRCodeEncoder, QRCodeDecoderErrorCorrectionLevel } = zxing
  const matrix = QRCodeEncoder.encode(text, QRCodeDecoderErrorCorrectionLevel.M).getMatrix()
  const modules = matrix.getWidth()
  const quiet = 4
  let path = ''
  for (let y = 0; y < modules; y++) {
    for (let x = 0; x < modules; x++) {
      if (matrix.get(x, y) === 1) path += `M${x + quiet} ${y + quiet}h1v1h-1z`
    }
  }
  const box = modules + quiet * 2
  return html`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${box} ${box}" width="${sizeMm}mm" height="${sizeMm}mm" shape-rendering="crispEdges" style="flex-shrink:0;display:block;"><path d="${path}" fill="#000"/></svg>`
}

function renderLabel(zxing: ZxingLibrary, item: LabelItem, format: LabelFormat) {
  const padding = 1.5
  const qrSize = format.height - padding * 2
  const compact = format.height < 32
  const titleSize = compact ? 8.5 : 10.5
  const lineSize = compact ? 6.5 : 7.5

  return html`
    <div class="label" style="width:${format.width}mm;height:${format.height}mm;padding:${padding}mm;gap:${padding}mm;">
      ${qrSvg(zxing, scanUrl(item.code), qrSize)}
      <div style="min-width:0;flex:1;display:flex;flex-direction:column;justify-content:center;gap:0.6mm;">
        <div style="font-family:monospace;font-weight:700;font-size:${titleSize}pt;line-height:1.15;overflow-wrap:anywhere;max-height:2.3em;overflow:hidden;">${item.title}</div>
        ${item.lines.filter(Boolean).map((line) => html`
          <div style="font-size:${lineSize}pt;line-height:1.2;color:#333;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${line}</div>`)}
        ${item.code !== item.title && html`
          <div style="font-family:monospace;font-size:${lineSize - 0.5}pt;color:#555;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${item.code}</div>`}
      </div>
    </div>`
}

// ZXing (already used by the scanner) is loaded on demand so pages that only
// offer printing don't ship the encoder up front.
export async function printLabels(items: LabelItem[], formatId: LabelFormatId) {
  if (items.length === 0) return
  const zxing = await import('@zxing/library')
  const format: LabelFormat = LABEL_FORMATS[formatId]
  const labels = items.map((item) => renderLabel(zxing, item, format))

  const sheet = format.sheet
  const pageSize = sheet ? `${sheet.pageWidth}mm ${sheet.pageHeight}mm` : `${format.width}mm ${format.height}mm`
  // Sheets centre the label grid on the page; rolls print one label per page.
  const layout = sheet
    ? html`.sheet{display:grid;grid-template-columns:repeat(${sheet.cols},${format.width}mm);grid-auto-rows:${format.height}mm;justify-content:center;align-content:start;padding-top:${(sheet.pageHeight - sheet.rows * format.height) / 2}mm;}
      .label:nth-child(${sheet.cols * sheet.rows}n){break-after:page;}`
    : html`.label{break-after:page;}.label:last-child{break-after:auto;}`

  const head = html`<style>
    @page{size:${pageSize};margin:0;}
    *{box-sizing:border-box;}
    body{margin:0;font-family:Arial,Helvetica,sans-serif;color:#000;background:#fff;-webkit-print-color-adjust:exact;print-color-adjust:exact;}
    .label{display:flex;align-items:center;overflow:hidden;}
    @media screen{body{background:#eee;padding:16px;}.sheet{gap:4px;}.label{background:#fff;outline:1px dashed #999;margin:0 auto 4px;}}
    ${layout}
  </style>`

  printDocument('Labels', html`<div class="sheet">${labels}</div>`, '', head)
}
