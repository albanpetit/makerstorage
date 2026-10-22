import type { Part, SortKey } from './types'
import { t } from '@/lib/i18n'

export const SORT_OPTIONS: { value: SortKey; label: string }[] = [
  { value: 'ref', get label() { return t('Reference (A→Z)') } },
  { value: 'crit', get label() { return t('Stock criticality') } },
  { value: 'qtyDesc', get label() { return t('Stock (high→low)') } },
  { value: 'qtyAsc', get label() { return t('Stock (low→high)') } },
  { value: 'priceDesc', get label() { return t('Unit price (high→low)') } },
]

export const STOCK_STATUS_META = {
  out: { get label() { return t('Out of stock') }, className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
  low: { get label() { return t('Low stock') }, className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
  ok: { get label() { return t('In stock') }, className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
}

export function stockStatusKey(quantity: number, threshold: number): keyof typeof STOCK_STATUS_META {
  if (quantity === 0) return 'out'
  if (quantity < threshold) return 'low'
  return 'ok'
}

export const LIFECYCLE_META: Record<Part['status'], { label: string; className: string }> = {
  active: { get label() { return t('Active') }, className: 'bg-muted text-muted-foreground' },
  discontinued: { get label() { return t('Discontinued') }, className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
  obsolete: { get label() { return t('Obsolete') }, className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
}

export function locationLabel(names: string[]): string {
  if (names.length === 0) return '—'
  if (names.length === 1) return names[0]
  return t('{name} +{count} more', { name: names[0], count: names.length - 1 })
}
