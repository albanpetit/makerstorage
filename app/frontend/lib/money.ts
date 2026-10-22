import { intlLocale } from '@/lib/i18n'

// Unit prices keep up to four decimals: small parts bought in volume cost a
// fraction of a cent (0.0021 for a 0402 resistor at 5000+).
export function formatUnitPrice(value: number) {
  return value.toLocaleString(intlLocale(), { minimumFractionDigits: 2, maximumFractionDigits: 4 })
}

// A quantity price break, as the server sends it.
export interface PriceBreak {
  quantity: number
  unit_price: number
}
