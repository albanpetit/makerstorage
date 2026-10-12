import { toast } from 'sonner'

import { html, printDocument } from '@/lib/print-document'

import { locationLabel } from './part-meta'
import type { Part, PartListFilters } from './types'

// Text starting with = + - @ (or a tab/CR) is run as a formula by Excel and
// friends, so user-entered fields get a leading quote. Plain numbers (e.g. a
// negative price) are left alone.
export function csvEscape(raw: string): string {
  const value = /^[=+\-@\t\r]/.test(raw) && !/^-?\d+(\.\d+)?$/.test(raw) ? `'${raw}` : raw
  if (/[",\n]/.test(value)) {
    return `"${value.replace(/"/g, '""')}"`
  }
  return value
}

export function exportCsv(parts: Part[]) {
  const headers = [
    "Name", "MPN", "SKU", "IPN", "Barcode", "Category", "Manufacturer", "Value", "Package",
    "Footprint", "Location", "Supplier", "Unit Price", "Quantity", "Min Stock Threshold",
    "Status", "Tags", "Description",
  ]
  const rows = parts.map((part) => [
    part.name,
    part.mpn || '',
    part.sku || '',
    part.ipn || '',
    part.barcode || '',
    part.category?.name || '',
    part.manufacturer || '',
    part.value || '',
    part.package_type || '',
    part.footprint?.name || '',
    part.location_names.join('; '),
    part.supplier_name || '',
    part.unit_price != null ? part.unit_price.toFixed(2) : '',
    String(part.total_quantity),
    String(part.min_stock_threshold),
    part.status,
    part.tag_names.join('; '),
    part.description || '',
  ])
  const csv = [ headers, ...rows ].map((row) => row.map(csvEscape).join(',')).join('\n')

  const blob = new Blob([ csv ], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `parts-${new Date().toISOString().slice(0, 10)}.csv`
  link.click()
  URL.revokeObjectURL(url)

  toast.success(`${parts.length} part${parts.length !== 1 ? 's' : ''} exported`, {
    description: link.download,
  })
}

export function printLabels(parts: Part[], target?: Window | null) {
  if (parts.length === 0) {
    target?.close()
    return
  }

  const labels = parts.map((part) => html`
    <div style="width:189px;height:95px;border:1px dashed #999;border-radius:4px;padding:8px 10px;box-sizing:border-box;page-break-inside:avoid;">
      <div style="font-family:monospace;font-weight:700;font-size:13px;">${part.mpn || part.sku || part.name}</div>
      <div style="font-size:9.5px;color:#555;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${part.name}</div>
      <div style="font-family:monospace;font-size:10px;margin-top:6px;">${locationLabel(part.location_names)}</div>
    </div>`)

  printDocument(
    'Labels',
    html`<div style="display:flex;flex-wrap:wrap;gap:10px;">${labels}</div>`,
    'font-family:Arial,sans-serif;padding:24px;background:#fff;',
    target,
  )
}

export function csrfToken(): string {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
}

// Fully serialized parts beyond the current page (PartsController#rows): either
// the given ids, or every part matching the list filters.
export async function fetchPartRows(body: { part_ids: number[] } | { filters: PartListFilters }): Promise<Part[]> {
  const response = await fetch('/parts/rows', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': csrfToken() },
    body: JSON.stringify(body),
  })
  if (!response.ok) throw new Error(`HTTP ${response.status}`)
  const data: { parts: Part[] } = await response.json()
  return data.parts
}

export interface ParsedImportRow {
  name: string
  category: string
  mpn: string
  sku: string
}

function splitCsvLine(line: string, sep: string): string[] {
  const out: string[] = []
  let cur = ''
  let inQuotes = false
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (inQuotes) {
      if (ch === '"') {
        if (line[i + 1] === '"') { cur += '"'; i++ } else { inQuotes = false }
      } else {
        cur += ch
      }
    } else if (ch === '"') {
      inQuotes = true
    } else if (ch === sep) {
      out.push(cur)
      cur = ''
    } else {
      cur += ch
    }
  }
  out.push(cur)
  return out
}

export function parseCsvPreview(text: string): { rows: ParsedImportRow[] } | { error: string } {
  const stripped = text.replace(/^\uFEFF/, '')
  const lines = stripped.split(/\r\n|\n|\r/).filter((l) => l.trim().length > 0)
  if (lines.length < 2) return { error: 'File is empty or has no data rows.' }

  const sep = lines[0].includes(';') ? ';' : ','
  const header = splitCsvLine(lines[0], sep).map((h) => h.trim().toLowerCase())
  const col = (names: string[]) => {
    for (const n of names) {
      const i = header.indexOf(n)
      if (i >= 0) return i
    }
    return -1
  }

  const iName = col([ 'name', 'designation', 'désignation' ])
  const iCategory = col([ 'category', 'categorie', 'catégorie' ])
  const iMpn = col([ 'mpn' ])
  const iSku = col([ 'sku', 'reference', 'ref', 'référence' ])

  if (iName < 0 || iCategory < 0) {
    return { error: 'Could not find "Name" and "Category" columns in the header row.' }
  }

  const rows: ParsedImportRow[] = []
  for (let i = 1; i < lines.length; i++) {
    const c = splitCsvLine(lines[i], sep)
    const name = (c[iName] || '').trim()
    const category = (c[iCategory] || '').trim()
    if (!name || !category) continue
    rows.push({
      name,
      category,
      mpn: iMpn >= 0 ? (c[iMpn] || '').trim() : '',
      sku: iSku >= 0 ? (c[iSku] || '').trim() : '',
    })
  }

  if (rows.length === 0) return { error: 'No valid rows found (each row needs a Name and Category).' }
  return { rows }
}
