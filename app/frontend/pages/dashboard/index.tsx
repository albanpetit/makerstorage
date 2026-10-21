import { Head, Link } from '@inertiajs/react'
import { useState } from 'react'
import { Package, Boxes, Coins, AlertTriangle, Plus } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { GlobalSearch } from '@/components/global-search'
import { PartDetailSheet } from '@/components/part-detail-sheet'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { t, intlLocale } from '@/lib/i18n'

interface Stats {
  references_count: number
  total_units: number
  stock_value: number
  alerts_count: number
  currency: string
}

interface CategoryBreakdownEntry {
  name: string
  count: number
  pct: number
}

interface LowStockPart {
  id: number
  reference: string
  name: string
  location_name: string | null
  quantity: number
  min_stock_threshold: number
}

interface RecentMovement {
  id: number
  part_id: number
  reference: string
  part_name: string
  location_name: string
  movement_type: 'in' | 'out' | 'adjustment'
  quantity_delta: number
  reason: string | null
  user_name: string | null
  created_at: string
}

interface DashboardProps {
  stats: Stats
  category_breakdown: CategoryBreakdownEntry[]
  low_stock_parts: LowStockPart[]
  recent_movements: RecentMovement[]
}

const CURRENCY_SYMBOLS: Record<string, string> = {
  EUR: '€',
  USD: '$',
  GBP: '£',
  CHF: 'CHF',
}

function formatMoney(value: number, currency: string) {
  const symbol = CURRENCY_SYMBOLS[currency] || currency
  return `${Math.round(value).toLocaleString(intlLocale())} ${symbol}`
}

const MOVEMENT_META: Record<RecentMovement['movement_type'], { label: string; className: string }> = {
  in: { get label() { return t('In') }, className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
  out: { get label() { return t('Out') }, className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
  adjustment: { get label() { return t('Adjustment') }, className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(intlLocale(), { day: '2-digit', month: '2-digit', year: 'numeric' })
}

export default function Dashboard({ stats, category_breakdown, low_stock_parts, recent_movements }: DashboardProps) {
  const { canWrite } = usePermissions()
  const [detailPartId, setDetailPartId] = useState<number | null>(null)
  const statCards = [
    { label: t('References'), value: stats.references_count.toLocaleString(intlLocale()), icon: Package },
    { label: t('Units in stock'), value: stats.total_units.toLocaleString(intlLocale()), icon: Boxes },
    { label: t('Stock value'), value: formatMoney(stats.stock_value, stats.currency), icon: Coins },
    { label: t('Low stock alerts'), value: stats.alerts_count.toLocaleString(intlLocale()), icon: AlertTriangle, alert: stats.alerts_count > 0 },
  ]

  return (
    <AppLayout
      header={
        <PageHeader title={t('Dashboard')} subtitle={t('Overview of your inventory')}>
          <GlobalSearch />
          {canWrite && (
            <Button size="sm" asChild>
              <Link href="/parts?new=1">
                <Plus className="size-4" />
                {t('New component')}
              </Link>
            </Button>
          )}
        </PageHeader>
      }
    >
      <Head title={t('Dashboard')} />

      <div className="space-y-6">
        {/* Stat cards */}
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          {statCards.map((stat) => (
            <Card key={stat.label}>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium text-muted-foreground">{stat.label}</CardTitle>
                <stat.icon className={`size-4 ${stat.alert ? 'text-destructive' : 'text-muted-foreground'}`} />
              </CardHeader>
              <CardContent>
                <div className={`text-2xl font-bold ${stat.alert ? 'text-destructive' : ''}`}>{stat.value}</div>
              </CardContent>
            </Card>
          ))}
        </div>

        <div className="grid gap-4 lg:grid-cols-[1.6fr_1fr]">
          {/* Low stock alerts */}
          <Card className="gap-0 py-0">
            <CardHeader className="flex flex-row items-center justify-between border-b py-4">
              <div>
                <CardTitle>{t('Low stock alerts')}</CardTitle>
                <p className="text-xs text-muted-foreground">{t('References under their minimum threshold')}</p>
              </div>
              <Link href="/alerts" className="text-sm font-medium text-muted-foreground hover:text-foreground">
                {t('See all →')}
              </Link>
            </CardHeader>
            <CardContent className="p-0">
              {low_stock_parts.length > 0 ? (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>{t('Reference')}</TableHead>
                      <TableHead>{t('Location')}</TableHead>
                      <TableHead className="text-right">{t('Stock')}</TableHead>
                      <TableHead className="text-right">{t('Threshold')}</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {low_stock_parts.map((part) => (
                      <TableRow key={part.id}>
                        <TableCell>
                          <Button
                            type="button"
                            variant="link"
                            onClick={() => setDetailPartId(part.id)}
                            className="h-auto p-0 text-left font-mono font-semibold text-foreground"
                          >
                            {part.reference}
                          </Button>
                          <div className="text-xs text-muted-foreground">{part.name}</div>
                        </TableCell>
                        <TableCell className="font-mono text-sm text-muted-foreground">
                          {part.location_name || '-'}
                        </TableCell>
                        <TableCell className="text-right font-mono font-semibold text-destructive">
                          {part.quantity}
                        </TableCell>
                        <TableCell className="text-right font-mono text-muted-foreground">
                          {part.min_stock_threshold}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              ) : (
                <p className="p-6 text-sm text-muted-foreground">{t('Nothing below threshold.')}</p>
              )}
            </CardContent>
          </Card>

          {/* Category breakdown */}
          <Card>
            <CardHeader>
              <CardTitle>{t('Breakdown by category')}</CardTitle>
            </CardHeader>
            <CardContent>
              {category_breakdown.length > 0 ? (
                <div className="space-y-3">
                  {category_breakdown.map((entry) => (
                    <div key={entry.name} className="space-y-1">
                      <div className="flex items-center justify-between text-sm">
                        <span className="font-medium">{entry.name}</span>
                        <span className="font-mono text-muted-foreground">{entry.count}</span>
                      </div>
                      <div className="h-2 w-full overflow-hidden rounded-full bg-muted">
                        <div
                          className="h-full rounded-full bg-primary"
                          style={{ width: `${entry.pct}%` }}
                        />
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-sm text-muted-foreground">{t('No parts yet.')}</p>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Recent movements */}
        <Card className="gap-0 py-0">
          <CardHeader className="flex flex-row items-center justify-between border-b py-4">
            <CardTitle>{t('Recent movements')}</CardTitle>
            <Link href="/stock_movements" className="text-sm font-medium text-muted-foreground hover:text-foreground">
              {t('See all →')}
            </Link>
          </CardHeader>
          <CardContent className="p-0">
            {recent_movements.length > 0 ? (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{t('Date')}</TableHead>
                    <TableHead>{t('Type')}</TableHead>
                    <TableHead>{t('Reference')}</TableHead>
                    <TableHead>{t('Reason')}</TableHead>
                    <TableHead className="text-right">{t('Qty')}</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {recent_movements.map((movement) => (
                    <TableRow key={movement.id}>
                      <TableCell className="whitespace-nowrap text-sm text-muted-foreground">
                        {formatDate(movement.created_at)}
                      </TableCell>
                      <TableCell>
                        <Badge className={MOVEMENT_META[movement.movement_type].className} variant="outline">
                          {MOVEMENT_META[movement.movement_type].label}
                        </Badge>
                      </TableCell>
                      <TableCell>
                        <Button
                          type="button"
                          variant="link"
                          onClick={() => setDetailPartId(movement.part_id)}
                          className="h-auto p-0 text-left font-mono font-semibold text-foreground"
                        >
                          {movement.reference}
                        </Button>
                        <div className="text-xs text-muted-foreground">{movement.location_name}</div>
                      </TableCell>
                      <TableCell className="max-w-[220px] truncate text-sm text-muted-foreground">
                        {movement.reason || '-'}
                      </TableCell>
                      <TableCell className="text-right font-mono">
                        {movement.quantity_delta > 0 ? `+${movement.quantity_delta}` : movement.quantity_delta}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            ) : (
              <p className="p-6 text-sm text-muted-foreground">{t('No stock movements yet.')}</p>
            )}
          </CardContent>
        </Card>

        {stats.references_count === 0 && (
          <Card>
            <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
              <Package className="size-8 text-muted-foreground" />
              <div>
                <p className="font-medium">{t('No parts yet')}</p>
                <p className="text-sm text-muted-foreground">{t('Add your first part to start tracking inventory.')}</p>
              </div>
              <Link href="/parts?new=1" className="text-sm font-medium underline underline-offset-4">
                {t('Add a part')}
              </Link>
            </CardContent>
          </Card>
        )}
      </div>

      {/* Part detail sidebar */}
      <PartDetailSheet
        partId={detailPartId}
        open={detailPartId !== null}
        onOpenChange={(open) => !open && setDetailPartId(null)}
      />
    </AppLayout>
  )
}
