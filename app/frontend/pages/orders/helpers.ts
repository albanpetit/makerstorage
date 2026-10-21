import { t, intlLocale } from '@/lib/i18n'
export const ORDER_STATUS_META = {
  pending: {
    get label() { return t('Pending') },
    className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400',
  },
  shipped: {
    get label() { return t('Shipped') },
    className: 'bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-400',
  },
  received: {
    get label() { return t('Received') },
    className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400',
  },
  cancelled: {
    get label() { return t('Cancelled') },
    className: 'bg-muted text-muted-foreground',
  },
} as const

export function formatMoney(value: number) {
  return `${value.toLocaleString(intlLocale(), { minimumFractionDigits: 2, maximumFractionDigits: 2 })} €`
}

export function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(intlLocale(), { day: '2-digit', month: '2-digit', year: 'numeric' })
}
