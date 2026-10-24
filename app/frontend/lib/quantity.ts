import { intlLocale, t } from '@/lib/i18n'

// The unit a part is counted in (Part::UNITS). Count units take whole
// quantities; measures (DECIMAL_UNITS) take up to three decimals: 2.5 m of
// wire, 340 g of filament, 0.5 L of isopropyl alcohol.
export const PART_UNITS = ['piece', 'meter', 'gram', 'kilogram', 'milliliter', 'liter', 'roll', 'lot'] as const
export type PartUnit = (typeof PART_UNITS)[number]

const DECIMAL_UNITS: readonly string[] = ['meter', 'gram', 'kilogram', 'milliliter', 'liter']
const UNIT_SYMBOLS: Record<string, string> = { meter: 'm', gram: 'g', kilogram: 'kg', milliliter: 'mL', liter: 'L' }

export function isDecimalUnit(unit?: string | null) {
  return !!unit && DECIMAL_UNITS.includes(unit)
}

// The unit's name for a picker.
export function unitLabel(unit: string) {
  switch (unit) {
    case 'piece': return t('Pieces')
    case 'meter': return t('Meters (m)')
    case 'gram': return t('Grams (g)')
    case 'kilogram': return t('Kilograms (kg)')
    case 'milliliter': return t('Milliliters (mL)')
    case 'liter': return t('Liters (L)')
    case 'roll': return t('Rolls')
    case 'lot': return t('Lots')
    default: return unit
  }
}

// Shown after a measure ("m", "kg"); empty for count units.
export function unitSymbol(unit?: string | null) {
  return (unit && UNIT_SYMBOLS[unit]) || ''
}

// A quantity in the viewer's locale with at most three decimals, followed by
// the unit's symbol for a measure: "12", "2.5 m", "0,5 L".
export function formatQuantity(value: number, unit?: string | null) {
  const number = value.toLocaleString(intlLocale(), { maximumFractionDigits: 3 })
  const symbol = unitSymbol(unit)
  return symbol ? `${number} ${symbol}` : number
}

// The number typed in +text+ ("2.5" or "2,5"), or null when it isn't one.
export function parseQuantity(text: string): number | null {
  const normalized = text.trim().replace(',', '.')
  if (!/^[-+]?(\d+(\.\d*)?|\.\d+)$/.test(normalized)) return null
  return Math.round(Number(normalized) * 1000) / 1000
}

// What a quantity field accepts as it's typed: digits, plus one decimal
// separator for a measure (both "." and "," so French keyboards work).
export function cleanQuantityInput(text: string, unit?: string | null) {
  if (!isDecimalUnit(unit)) return text.replace(/[^0-9]/g, '')
  const cleaned = text.replace(/[^0-9.,]/g, '')
  const separator = cleaned.search(/[.,]/)
  if (separator < 0) return cleaned
  return cleaned.slice(0, separator + 1) + cleaned.slice(separator + 1).replace(/[.,]/g, '').slice(0, 3)
}

// The <Input type="number"> step for a quantity of +unit+.
export function quantityStep(unit?: string | null) {
  return isDecimalUnit(unit) ? 'any' : '1'
}

// Adds quantities without float noise (0.1 + 0.2 = 0.3).
export function sumQuantities(values: number[]) {
  return Math.round(values.reduce((sum, value) => sum + value, 0) * 1000) / 1000
}
