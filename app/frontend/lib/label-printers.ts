// Network label printers (LabelPrintersController): the browser renders each
// label at the printer's geometry and posts the bitmaps; the server sends them
// to the printer.

import { csrfToken } from '@/components/parts/csv'
import { type LabelGeometry, bitmapToBase64, renderLabelBitmap } from '@/lib/label-bitmap'
import type { LabelItem } from '@/lib/labels'
import { t } from '@/lib/i18n'

export interface LabelPrinter extends LabelGeometry {
  id: number
  name: string
  // "62 × 29 mm"
  size: string
}

export interface LabelPrintersPayload {
  enabled: boolean
  printers: LabelPrinter[]
}

// Must match LabelPrintersController::MAX_LABELS.
const BATCH_SIZE = 50

export async function fetchLabelPrinters(): Promise<LabelPrintersPayload> {
  const response = await fetch('/label_printers', { headers: { Accept: 'application/json' } })
  if (!response.ok) throw new Error(`HTTP ${response.status}`)
  return response.json()
}

// Prints +items+ on +printer+, a batch per request. Throws an Error carrying
// the server's message (e.g. printer unreachable).
export async function printOnLabelPrinter(printer: LabelPrinter, items: LabelItem[]) {
  const zxing = await import('@zxing/library')
  for (let start = 0; start < items.length; start += BATCH_SIZE) {
    const labels = items.slice(start, start + BATCH_SIZE).map((item) => bitmapToBase64(renderLabelBitmap(zxing, item, printer)))
    const response = await fetch(`/label_printers/${printer.id}/print`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': csrfToken() },
      body: JSON.stringify({ labels }),
    })
    if (!response.ok) {
      const data = await response.json().catch(() => null)
      throw new Error(data?.error || t('The printer could not be reached (HTTP {status}).', { status: response.status }))
    }
  }
}
