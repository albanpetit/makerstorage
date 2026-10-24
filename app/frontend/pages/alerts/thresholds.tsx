import { Head, Link, router } from '@inertiajs/react'
import { useMemo, useState } from 'react'
import { ArrowLeft, Check, TrendingDown, TrendingUp } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { PartDetailSheet } from '@/components/part-detail-sheet'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Checkbox } from '@/components/ui/checkbox'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { t, intlLocale, tn } from '@/lib/i18n'

interface Row {
  id: number
  reference: string
  name: string
  ipn: string | null
  category: { name: string; color: string | null } | null
  quantity: number
  min_stock_threshold: number
  suggested_threshold: number | null
  consumed: number
  movements: number
  monthly_rate: number
  days_left: number | null
  cover_days: number
  last_used_at: string | null
  differs: boolean
}

interface ThresholdsPageProps {
  /** Only the rows to review unless +show_all+. */
  rows: Row[]
  show_all: boolean
  counts: { differing: number; all: number }
  window_days: number
  cover_days: number
}

export default function AlertsThresholds({ rows, show_all: showAll, counts, window_days, cover_days }: ThresholdsPageProps) {
  const { canWrite } = usePermissions()
  const [selected, setSelected] = useState<Set<number>>(new Set())
  const [detailPartId, setDetailPartId] = useState<number | null>(null)

  const visible = useMemo(() => (showAll ? rows : rows.filter((row) => row.differs)), [rows, showAll])
  const setShowAll = (all: boolean) => {
    if (all === showAll) return
    router.get('/alerts/thresholds', all ? { all: '1' } : {}, { preserveScroll: true, preserveState: true })
  }
  const selectable = visible.filter((row) => row.suggested_threshold != null && row.suggested_threshold !== row.min_stock_threshold)
  const allSelected = selectable.length > 0 && selectable.every((row) => selected.has(row.id))

  const toggle = (id: number, checked: boolean) => {
    setSelected((current) => {
      const next = new Set(current)
      if (checked) next.add(id)
      else next.delete(id)
      return next
    })
  }

  const apply = (ids: number[]) => {
    router.post('/alerts/thresholds', { part_ids: ids }, {
      preserveScroll: true,
      onSuccess: () => setSelected(new Set()),
    })
  }

  return (
    <AppLayout
      header={
        <PageHeader
          title={t('Suggested thresholds')}
          subtitle={t('Low-stock thresholds from each component’s use over the last {days} days', { days: window_days })}
        >
          <Button variant="outline" size="sm" asChild>
            <Link href="/alerts">
              <ArrowLeft className="size-4" />
              {t('Alerts')}
            </Link>
          </Button>
          {canWrite && selected.size > 0 && (
            <Button size="sm" onClick={() => apply([...selected])}>
              <Check className="size-4" />
              {tn('Apply to {count} component', 'Apply to {count} components', selected.size)}
            </Button>
          )}
        </PageHeader>
      }
    >
      <Head title={t('Suggested thresholds')} />

      <div className="space-y-4">
        <FlashMessages />

        <p className="max-w-3xl text-sm text-muted-foreground">
          {t('A suggested threshold holds {days} days of use, or the supplier lead time plus a week when longer, so an alert leaves time to reorder. Builds, scanner and manual stock-outs count as use; zone moves and loans don’t. Change the period and the days covered in Settings → Inventory.', { days: cover_days })}
        </p>

        <div className="flex flex-wrap items-center gap-2">
          {[
            { value: false, label: t('To review'), count: counts.differing },
            { value: true, label: t('All used components'), count: counts.all },
          ].map((tab) => (
            <Button
              key={String(tab.value)}
              variant="ghost"
              onClick={() => { setShowAll(tab.value); setSelected(new Set()) }}
              className={`h-8 gap-1.5 border px-3 ${
                showAll === tab.value
                  ? 'border-foreground bg-foreground text-background hover:bg-foreground/90 hover:text-background dark:hover:bg-foreground/90'
                  : 'border-border bg-background'
              }`}
            >
              {tab.label}
              <span className="font-mono opacity-60">{tab.count}</span>
            </Button>
          ))}
        </div>

        {visible.length === 0 ? (
          <Card>
            <CardContent className="py-10 text-center text-sm text-muted-foreground">
              {counts.all === 0
                ? t('No component was used in the last {days} days.', { days: window_days })
                : t('Every threshold is in line with recent use.')}
            </CardContent>
          </Card>
        ) : (
          <Card className="overflow-hidden py-0">
            <Table>
              <TableHeader>
                <TableRow>
                  {canWrite && (
                    <TableHead className="w-10">
                      <Checkbox
                        aria-label={t('Select all')}
                        checked={allSelected}
                        disabled={selectable.length === 0}
                        onCheckedChange={(checked) => setSelected(checked === true ? new Set(selectable.map((row) => row.id)) : new Set())}
                      />
                    </TableHead>
                  )}
                  <TableHead>{t('Component')}</TableHead>
                  <TableHead className="text-right">{t('Used')}</TableHead>
                  <TableHead className="text-right">{t('Per month')}</TableHead>
                  <TableHead className="text-right">{t('In stock')}</TableHead>
                  <TableHead className="text-right">{t('Stock lasts')}</TableHead>
                  <TableHead className="text-right">{t('Threshold')}</TableHead>
                  <TableHead className="text-right">{t('Suggested')}</TableHead>
                  {canWrite && <TableHead className="w-20" />}
                </TableRow>
              </TableHeader>
              <TableBody>
                {visible.map((row) => {
                  const canApply = row.suggested_threshold != null && row.suggested_threshold !== row.min_stock_threshold
                  const raising = row.suggested_threshold != null && row.suggested_threshold > row.min_stock_threshold
                  return (
                    <TableRow key={row.id}>
                      {canWrite && (
                        <TableCell>
                          <Checkbox
                            aria-label={t('Select {name}', { name: row.reference })}
                            checked={selected.has(row.id)}
                            disabled={!canApply}
                            onCheckedChange={(checked) => toggle(row.id, checked === true)}
                          />
                        </TableCell>
                      )}
                      <TableCell className="max-w-[260px]">
                        <Button variant="link" className="h-auto p-0 font-mono font-semibold" onClick={() => setDetailPartId(row.id)}>
                          {row.reference}
                        </Button>
                        <div className="truncate text-xs text-muted-foreground">
                          {row.ipn && <span className="mr-1.5 font-mono">{row.ipn}</span>}
                          {row.name}
                        </div>
                      </TableCell>
                      <TableCell className="text-right font-mono">
                        {row.consumed.toLocaleString(intlLocale())}
                        <div className="text-xs text-muted-foreground">{tn('{count} take', '{count} takes', row.movements)}</div>
                      </TableCell>
                      <TableCell className="text-right font-mono">{row.monthly_rate.toLocaleString(intlLocale(), { maximumFractionDigits: 1 })}</TableCell>
                      <TableCell className="text-right font-mono">{row.quantity.toLocaleString(intlLocale())}</TableCell>
                      <TableCell className={`text-right font-mono ${row.days_left != null && row.days_left < row.cover_days ? 'text-amber-600 dark:text-amber-400' : ''}`}>
                        {row.days_left != null ? tn('{count} day', '{count} days', row.days_left) : '—'}
                      </TableCell>
                      <TableCell className="text-right font-mono">{row.min_stock_threshold}</TableCell>
                      <TableCell className="text-right font-mono font-semibold">
                        {row.suggested_threshold != null ? (
                          <span className="inline-flex items-center gap-1">
                            {canApply && (raising
                              ? <TrendingUp className="size-3.5 text-amber-600 dark:text-amber-400" />
                              : <TrendingDown className="size-3.5 text-emerald-600 dark:text-emerald-400" />)}
                            {row.suggested_threshold}
                          </span>
                        ) : (
                          <span className="text-xs font-normal text-muted-foreground" title={t('Not enough uses yet to suggest a threshold.')}>—</span>
                        )}
                      </TableCell>
                      {canWrite && (
                        <TableCell className="text-right">
                          {canApply && (
                            <Button variant="outline" size="sm" onClick={() => apply([row.id])}>{t('Apply')}</Button>
                          )}
                        </TableCell>
                      )}
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
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
