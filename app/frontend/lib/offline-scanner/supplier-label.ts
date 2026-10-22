// Port of SupplierLabel.parse (app/services/supplier_label.rb) so the Scanner
// page can read DigiKey, Mouser and LCSC bag labels without a network. Keep
// the two in step.

export interface SupplierLabel {
  provider: string | null
  provider_name: string
  mpn: string | null
  supplier_sku: string | null
  customer_part_number: string | null
  manufacturer: string | null
  quantity: number | null
  order_number: string | null
  lot: string | null
  date_code: string | null
  country_of_origin: string | null
}

const ECIA_HEADER = '[)>'
const GS = '\u001D'
const RS = '\u001E'
const EOT = '\u0004'
const SEPARATOR_STAND_INS: Array<[string, string[]]> = [
  [GS, ['{GS}', '<GS>', '^]', '␝']],
  [RS, ['{RS}', '<RS>', '^^', '␞']],
  [EOT, ['{EOT}', '<EOT>', '^D', '␄']],
]

type Field = 'supplier_sku' | 'mpn' | 'customer_part_number' | 'manufacturer' | 'sales_order' | 'invoice'
  | 'line_item' | 'purchase_order' | 'quantity' | 'lot' | 'date_code' | 'country_of_origin'

const IDENTIFIERS: Record<string, Field> = {
  '30P': 'supplier_sku',
  '1P': 'mpn',
  P: 'customer_part_number',
  '1V': 'manufacturer',
  '1K': 'sales_order',
  '11K': 'invoice',
  '14K': 'line_item',
  K: 'purchase_order',
  Q: 'quantity',
  '1T': 'lot',
  '9D': 'date_code',
  '10D': 'date_code',
  '4L': 'country_of_origin',
}
// Longest first so `30P` and `1P` aren't mistaken for `P`.
const IDENTIFIER_PATTERN = new RegExp(
  `^(${Object.keys(IDENTIFIERS).sort((a, b) => b.length - a.length).join('|')})([\\s\\S]*)$`,
)

const PROVIDER_NAMES: Record<string, string> = { digikey: 'DigiKey', mouser: 'Mouser', lcsc: 'LCSC' }
const MAX_INTEGER = 2_147_483_647

function presence(value: string | undefined | null): string | null {
  const trimmed = value?.trim()
  return trimmed ? trimmed : null
}

function buildLabel(fields: Partial<Record<Field | 'provider', string | null>>): SupplierLabel {
  const rawQuantity = fields.quantity ?? ''
  let quantity = /^\d+$/.test(rawQuantity) ? Number.parseInt(rawQuantity, 10) : null
  if (quantity !== null && (quantity <= 0 || quantity > MAX_INTEGER)) quantity = null
  const provider = fields.provider ?? null

  return {
    provider,
    provider_name: (provider && PROVIDER_NAMES[provider]) || 'Supplier',
    mpn: fields.mpn ?? null,
    supplier_sku: fields.supplier_sku ?? null,
    customer_part_number: fields.customer_part_number ?? null,
    manufacturer: fields.manufacturer ?? null,
    quantity,
    order_number: fields.sales_order ?? fields.invoice ?? fields.purchase_order ?? null,
    lot: fields.lot ?? null,
    date_code: fields.date_code ?? null,
    country_of_origin: fields.country_of_origin ?? null,
  }
}

function parseEcia(raw: string): SupplierLabel | null {
  let text = raw
  for (const [char, standIns] of SEPARATOR_STAND_INS) {
    for (const standIn of standIns) text = text.split(standIn).join(char)
  }
  const start = text.indexOf(`${ECIA_HEADER}${RS}06${GS}`)
  if (start < 0) return null

  const body = text.slice(start + ECIA_HEADER.length + 4).split(RS)[0] ?? ''
  const fields: Partial<Record<Field, string | null>> = {}
  for (const field of body.split(GS)) {
    const match = field.trim().match(IDENTIFIER_PATTERN)
    if (!match) continue
    const key = IDENTIFIERS[match[1]]
    fields[key] ??= presence(match[2])
  }
  if (Object.keys(fields).length === 0) return null

  // DigiKey labels carry its own part number (`30P`, or a `-ND` suffix) and
  // pick/label ids (`12Z`, `13Z`, `20Z`); Mouser's carry a line item (`14K`)
  // and the manufacturer name (`1V`).
  const segments = body.split(GS).map((segment) => segment.trim())
  let provider: string | null = null
  if ('supplier_sku' in fields || (fields.customer_part_number ?? '').endsWith('-ND') || segments.some((segment) => /^(12|13|20)Z/.test(segment))) {
    provider = 'digikey'
  } else if ('line_item' in fields || 'manufacturer' in fields) {
    provider = 'mouser'
  }

  // DigiKey prints its own part number in the customer part number field when
  // the order line had no customer reference.
  if (provider === 'digikey' && !fields.supplier_sku && (fields.customer_part_number ?? '').endsWith('-ND')) {
    fields.supplier_sku = fields.customer_part_number
    delete fields.customer_part_number
  }

  return buildLabel({ ...fields, provider })
}

function parseLcsc(text: string): SupplierLabel {
  const fields: Record<string, string | null> = {}
  for (const pair of text.replace(/^\{/, '').replace(/\}$/, '').split(',')) {
    if (pair === '') continue
    const separator = pair.indexOf(':')
    const key = (separator < 0 ? pair : pair.slice(0, separator)).trim()
    const value = separator < 0 ? null : presence(pair.slice(separator + 1))
    fields[key] = value
  }
  return buildLabel({ provider: 'lcsc', mpn: fields.pm, supplier_sku: fields.pc, quantity: fields.qty, sales_order: fields.on })
}

/** A supplier bag label, or null when `raw` isn't one or carries no part number. */
export function parseSupplierLabel(raw: string): SupplierLabel | null {
  let label: SupplierLabel | null = null
  if (raw.includes(ECIA_HEADER)) {
    label = parseEcia(raw)
  } else if (/^\{[\s\S]*\bpc:[\s\S]*\}$/.test(raw.trim())) {
    label = parseLcsc(raw.trim())
  }
  return label && (label.mpn || label.supplier_sku || label.customer_part_number) ? label : null
}

/** The receipt movement's reference, e.g. "DigiKey 84512345" (SupplierLabel#movement_reference). */
export function movementReference(label: SupplierLabel): string {
  return `${label.provider_name} ${label.order_number || 'label'}`
}
