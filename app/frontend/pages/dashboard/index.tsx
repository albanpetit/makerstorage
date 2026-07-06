import { Head, Link } from '@inertiajs/react'
import { Package, Boxes, Coins, AlertTriangle } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
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

interface RecentMovement {
  id: number
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
  return `${Math.round(value).toLocaleString()} ${symbol}`
}

const MOVEMENT_META: Record<RecentMovement['movement_type'], { label: string; className: string }> = {
  in: { label: 'In', className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
  out: { label: 'Out', className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
  adjustment: { label: 'Adjustment', className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, { day: '2-digit', month: '2-digit', year: 'numeric' })
}

export default function Dashboard({ stats, category_breakdown, recent_movements }: DashboardProps) {
  const breadcrumbs = [{ label: 'Dashboard' }]

  const statCards = [
    { label: 'References', value: stats.references_count.toLocaleString(), icon: Package },
    { label: 'Units in stock', value: stats.total_units.toLocaleString(), icon: Boxes },
    { label: 'Stock value', value: formatMoney(stats.stock_value, stats.currency), icon: Coins },
    { label: 'Low stock alerts', value: stats.alerts_count.toLocaleString(), icon: AlertTriangle, alert: stats.alerts_count > 0 },
  ]

  return (
    <AppLayout breadcrumbs={breadcrumbs}>
      <Head title="Dashboard" />

      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Dashboard</h1>
          <p className="text-muted-foreground">Overview of your inventory</p>
        </div>

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

        <div className="grid gap-4 lg:grid-cols-2">
          {/* Category breakdown */}
          <Card>
            <CardHeader>
              <CardTitle>Breakdown by category</CardTitle>
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
                <p className="text-sm text-muted-foreground">No parts yet.</p>
              )}
            </CardContent>
          </Card>

          {/* Recent movements */}
          <Card>
            <CardHeader>
              <CardTitle>Recent movements</CardTitle>
            </CardHeader>
            <CardContent>
              {recent_movements.length > 0 ? (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Date</TableHead>
                      <TableHead>Part</TableHead>
                      <TableHead>Type</TableHead>
                      <TableHead className="text-right">Qty</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {recent_movements.map((movement) => (
                      <TableRow key={movement.id}>
                        <TableCell className="whitespace-nowrap text-sm text-muted-foreground">
                          {formatDate(movement.created_at)}
                        </TableCell>
                        <TableCell>
                          <div className="font-medium">{movement.part_name}</div>
                          <div className="text-xs text-muted-foreground">
                            {movement.location_name}
                            {movement.reason ? ` · ${movement.reason}` : ''}
                          </div>
                        </TableCell>
                        <TableCell>
                          <Badge className={MOVEMENT_META[movement.movement_type].className} variant="outline">
                            {MOVEMENT_META[movement.movement_type].label}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-right font-mono">
                          {movement.quantity_delta > 0 ? `+${movement.quantity_delta}` : movement.quantity_delta}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              ) : (
                <p className="text-sm text-muted-foreground">No stock movements yet.</p>
              )}
            </CardContent>
          </Card>
        </div>

        {stats.references_count === 0 && (
          <Card>
            <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
              <Package className="size-8 text-muted-foreground" />
              <div>
                <p className="font-medium">No parts yet</p>
                <p className="text-sm text-muted-foreground">Add your first part to start tracking inventory.</p>
              </div>
              <Link href="/parts/new" className="text-sm font-medium underline underline-offset-4">
                Add a part
              </Link>
            </CardContent>
          </Card>
        )}
      </div>
    </AppLayout>
  )
}
