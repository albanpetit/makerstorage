import { Head, router } from '@inertiajs/react'
import { useState } from 'react'
import { Coins, Download, Package, Tag } from 'lucide-react'
import { AppLayout } from '@/layouts/app-layout'
import { PageHeader } from '@/components/page-header'
import { PartDetailSheet } from '@/components/part-detail-sheet'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { t, tn, intlLocale } from '@/lib/i18n'
import { formatUnitPrice } from '@/lib/money'

type ValuationMethod = 'current' | 'last' | 'average'

interface ValuedPart {
  id: number
  reference: string
  ipn: string | null
  name: string
  category: string | null
  quantity: number
  unit_value: number | null
  value: number
  source: 'purchase' | 'current' | null
}

interface Breakdown {
  id: number | null
  name: string | null
  color?: string | null
  value: number
  parts: number
}

interface StockValuePageProps {
  valuation_method: ValuationMethod
  currency: string
  total: number
  parts_count: number
  purchase_priced_count: number
  unpriced_count: number
  categories: Breakdown[]
  zones: Breakdown[]
  parts: ValuedPart[]
  unpriced_parts: ValuedPart[]
}

const METHODS: { value: ValuationMethod; readonly label: string; readonly hint: string }[] = [
  {
    value: 'current',
    get label() { return t('Current price') },
    get hint() { return t('Each part at its unit price (its preferred supplier’s).') },
  },
  {
    value: 'last',
    get label() { return t('Last purchase price') },
    get hint() { return t('Each part at the price of its latest received order, else its current price.') },
  },
  {
    value: 'average',
    get label() { return t('Average purchase price') },
    get hint() { return t('Each part at the average price paid on its received orders (weighted by quantity), else its current price.') },
  },
]

function formatMoney(value: number, currency: string) {
  try {
    return new Intl.NumberFormat(intlLocale(), { style: 'currency', currency, maximumFractionDigits: 2 }).format(value)
  } catch {
    return `${value.toFixed(2)} ${currency}`
  }
}

// What the stock on hand is worth: total, by category, by top-level zone and
// part, valued at current or purchase prices (StockValuation).
export default function StockValueShow({
  valuation_method,
  currency,
  total,
  parts_count,
  purchase_priced_count,
  unpriced_count,
  categories,
  zones,
  parts,
  unpriced_parts,
}: StockValuePageProps) {
  const [detailPartId, setDetailPartId] = useState<number | null>(null)
  const method = METHODS.find((m) => m.value === valuation_method) ?? METHODS[0]

  const changeMethod = (value: string) =>
    router.get('/stock_value', value === 'current' ? {} : { method: value }, { preserveScroll: true, preserveState: true })

  const csvHref = `/stock_value.csv${valuation_method === 'current' ? '' : `?method=${valuation_method}`}`

  return (
    <AppLayout
      header={
        <PageHeader title={t('Stock value')} subtitle={t('What the stock on hand is worth, by category, zone and part')}>
          <Select value={valuation_method} onValueChange={changeMethod}>
            <SelectTrigger size="sm" className="w-52" aria-label={t('Valuation')}>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {METHODS.map((m) => (
                <SelectItem key={m.value} value={m.value}>{m.label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Button size="sm" variant="outline" asChild>
            <a href={csvHref}>
              <Download className="size-4" />
              {t('Export CSV')}
            </a>
          </Button>
        </PageHeader>
      }
    >
      <Head title={t('Stock value')} />

      <div className="space-y-6">
        <p className="text-sm text-muted-foreground">{method.hint}</p>

        <div className="grid gap-4 sm:grid-cols-3">
          <StatCard icon={Coins} label={t('Total value')} value={formatMoney(total, currency)} detail={method.label} />
          <StatCard
            icon={Package}
            label={t('Parts in stock')}
            value={parts_count.toLocaleString(intlLocale())}
            detail={
              valuation_method === 'current'
                ? t('Valued at their current price')
                : tn('{count} valued at purchase prices', '{count} valued at purchase prices', purchase_priced_count)
            }
          />
          <StatCard
            icon={Tag}
            label={t('Without a price')}
            value={unpriced_count.toLocaleString(intlLocale())}
            detail={unpriced_count > 0 ? t('Counted as zero: add a price to value them') : t('Every part in stock has a price')}
            warning={unpriced_count > 0}
          />
        </div>

        <div className="grid gap-4 lg:grid-cols-2">
          <BreakdownCard
            title={t('By category')}
            entries={categories}
            total={total}
            currency={currency}
            empty={t('Nothing in stock yet.')}
            fallbackName={t('No category')}
          />
          <BreakdownCard
            title={t('By zone')}
            description={t('Top-level zones, sub-zones included')}
            entries={zones}
            total={total}
            currency={currency}
            empty={t('Nothing in stock yet.')}
            fallbackName={t('Unknown zone')}
          />
        </div>

        <Card className="gap-0 overflow-hidden py-0">
          <CardHeader className="border-b px-4 py-3">
            <CardTitle className="text-base">{t('Most valuable parts')}</CardTitle>
            {parts_count > parts.length && (
              <CardDescription>{t('The first {count}: the CSV has every part.', { count: parts.length })}</CardDescription>
            )}
          </CardHeader>
          <PartsTable parts={parts} currency={currency} onOpen={setDetailPartId} />
        </Card>

        {unpriced_parts.length > 0 && (
          <Card className="gap-0 overflow-hidden py-0">
            <CardHeader className="border-b px-4 py-3">
              <CardTitle className="text-base">{t('Parts in stock without a price')}</CardTitle>
              <CardDescription>{t('Open a part to add its supplier price.')}</CardDescription>
            </CardHeader>
            <PartsTable parts={unpriced_parts} currency={currency} onOpen={setDetailPartId} />
          </Card>
        )}
      </div>

      <PartDetailSheet
        partId={detailPartId}
        open={detailPartId !== null}
        onOpenChange={(open) => !open && setDetailPartId(null)}
      />
    </AppLayout>
  )
}

function StatCard({
  icon: Icon,
  label,
  value,
  detail,
  warning = false,
}: {
  icon: typeof Coins
  label: string
  value: string
  detail: string
  warning?: boolean
}) {
  return (
    <Card className="py-4">
      <CardContent className="flex items-start justify-between gap-3 px-4">
        <div className="min-w-0">
          <div className="text-xs text-muted-foreground">{label}</div>
          <div className={`mt-1 font-mono text-2xl font-bold ${warning ? 'text-amber-600 dark:text-amber-400' : ''}`}>{value}</div>
          <div className="mt-1 text-xs text-muted-foreground">{detail}</div>
        </div>
        <div className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-muted text-muted-foreground">
          <Icon className="size-4" />
        </div>
      </CardContent>
    </Card>
  )
}

function BreakdownCard({
  title,
  description,
  entries,
  total,
  currency,
  empty,
  fallbackName,
}: {
  title: string
  description?: string
  entries: Breakdown[]
  total: number
  currency: string
  empty: string
  fallbackName: string
}) {
  const max = Math.max(0, ...entries.map((entry) => entry.value))

  return (
    <Card className="gap-3">
      <CardHeader>
        <CardTitle className="text-base">{title}</CardTitle>
        {description && <CardDescription>{description}</CardDescription>}
      </CardHeader>
      <CardContent className="space-y-3">
        {entries.length === 0 && <p className="text-sm text-muted-foreground">{empty}</p>}
        {entries.map((entry) => {
          const share = total > 0 ? (entry.value / total) * 100 : 0
          return (
            <div key={entry.id ?? 'none'} className="space-y-1">
              <div className="flex items-baseline justify-between gap-3 text-sm">
                <span className="flex min-w-0 items-center gap-2">
                  {entry.color && <span className="size-2.5 shrink-0 rounded-sm" style={{ backgroundColor: entry.color }} />}
                  <span className="truncate">{entry.name ?? fallbackName}</span>
                  <span className="shrink-0 text-xs text-muted-foreground">{tn('{count} part', '{count} parts', entry.parts)}</span>
                </span>
                <span className="shrink-0 font-mono">
                  {formatMoney(entry.value, currency)}
                  <span className="ml-2 inline-block w-10 text-right text-xs text-muted-foreground">
                    {share.toLocaleString(intlLocale(), { maximumFractionDigits: 0 })} %
                  </span>
                </span>
              </div>
              <div className="h-1.5 overflow-hidden rounded-full bg-muted">
                <div className="h-full rounded-full bg-blue-600 dark:bg-blue-400" style={{ width: `${max > 0 ? (entry.value / max) * 100 : 0}%` }} />
              </div>
            </div>
          )
        })}
      </CardContent>
    </Card>
  )
}

function PartsTable({ parts, currency, onOpen }: { parts: ValuedPart[]; currency: string; onOpen: (id: number) => void }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{t('Part')}</TableHead>
          <TableHead className="hidden sm:table-cell">{t('Category')}</TableHead>
          <TableHead className="text-right">{t('Quantity')}</TableHead>
          <TableHead className="text-right">{t('Unit value')}</TableHead>
          <TableHead className="text-right">{t('Value')}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {parts.map((part) => (
          <TableRow key={part.id} className="cursor-pointer" onClick={() => onOpen(part.id)}>
            <TableCell className="max-w-64">
              <div className="truncate font-medium">{part.reference}</div>
              <div className="truncate text-xs text-muted-foreground">
                {part.ipn ? `${part.ipn} · ` : ''}
                {part.name}
              </div>
            </TableCell>
            <TableCell className="hidden text-sm text-muted-foreground sm:table-cell">{part.category ?? '—'}</TableCell>
            <TableCell className="text-right font-mono">{part.quantity.toLocaleString(intlLocale())}</TableCell>
            <TableCell className="text-right">
              <span className="font-mono">{part.unit_value != null ? formatUnitPrice(part.unit_value) : '—'}</span>
              {part.source === 'purchase' && (
                <Badge variant="outline" className="ml-2 hidden md:inline-flex">{t('purchase')}</Badge>
              )}
            </TableCell>
            <TableCell className="text-right font-mono font-semibold">{formatMoney(part.value, currency)}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  )
}
