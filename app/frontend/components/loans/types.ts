export type LoanStatus = 'open' | 'overdue' | 'returned'
import { t, intlLocale } from '@/lib/i18n'

export interface MemberOption {
  id: number
  name: string
  email: string
}

// A part with stock somewhere, and the zones holding it (fullest first).
export interface LendablePart {
  id: number
  reference: string
  ipn: string | null
  name: string
  locations: { id: number; name: string; quantity: number }[]
}

export const LOAN_STATUS_META: Record<LoanStatus, { label: string; className: string }> = {
  open: { get label() { return t('Out') }, className: 'bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-400' },
  overdue: { get label() { return t('Overdue') }, className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
  returned: { get label() { return t('Returned') }, className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
}

export function formatDate(iso: string) {
  // Dates without a time ("2026-10-20") are calendar days: read them as local
  // midnight, not UTC, so they don't shift a day west of Greenwich.
  const date = /^\d{4}-\d{2}-\d{2}$/.test(iso) ? new Date(`${iso}T00:00:00`) : new Date(iso)
  return date.toLocaleDateString(intlLocale(), { day: '2-digit', month: '2-digit', year: 'numeric' })
}
