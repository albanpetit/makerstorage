import type { Part, SortKey } from './types'

export const SORT_OPTIONS: { value: SortKey; label: string }[] = [
  { value: 'ref', label: 'Reference (A→Z)' },
  { value: 'crit', label: 'Stock criticality' },
  { value: 'qtyDesc', label: 'Stock (high→low)' },
  { value: 'qtyAsc', label: 'Stock (low→high)' },
  { value: 'priceDesc', label: 'Unit price (high→low)' },
]

export const STOCK_STATUS_META = {
  out: { label: 'Out of stock', className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
  low: { label: 'Low stock', className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
  ok: { label: 'In stock', className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
}

export function stockStatusKey(quantity: number, threshold: number): keyof typeof STOCK_STATUS_META {
  if (quantity === 0) return 'out'
  if (quantity < threshold) return 'low'
  return 'ok'
}

export const LIFECYCLE_META: Record<Part['status'], { label: string; className: string }> = {
  active: { label: 'Active', className: 'bg-muted text-muted-foreground' },
  discontinued: { label: 'Discontinued', className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
  obsolete: { label: 'Obsolete', className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
}

export function locationLabel(names: string[]): string {
  if (names.length === 0) return '—'
  if (names.length === 1) return names[0]
  return `${names[0]} +${names.length - 1} more`
}
