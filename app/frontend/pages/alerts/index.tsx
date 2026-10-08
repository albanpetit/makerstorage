import { Head, router } from '@inertiajs/react'
import { useMemo, useState } from 'react'
import { AlertTriangle, CheckCircle2, FileText, Printer } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { html, printDocument } from '@/lib/print-document'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { PartDetailSheet } from '@/components/part-detail-sheet'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

interface Alert {
  id: number
  reference: string
  name: string
  category: { name: string; color: string | null } | null
  location_name: string | null
  quantity: number
  min_stock_threshold: number
  severity: 'critical' | 'low'
  supplier_name: string | null
  unit_price: number
  reorder_quantity: number
}

interface Order {
  id: number
  reference: string | null
  supplier_name: string
  ordered_at: string | null
  status: string
  total_amount: number
  line_count: number
}

interface AlertsPageProps {
  alerts: Alert[]
  orders: Order[]
}

const SEVERITY_META: Record<Alert['severity'], { label: string; className: string; border: string }> = {
  critical: { label: 'Critical', className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400', border: 'border-l-red-500' },
  low: { label: 'Low stock', className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400', border: 'border-l-amber-500' },
}

const ORDER_STATUS_META: Record<string, { label: string; className: string; next: string | null }> = {
  pending: { label: 'Pending', className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400', next: 'Mark shipped' },
  shipped: { label: 'Shipped', className: 'bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-400', next: 'Mark received' },
  received: { label: 'Received', className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400', next: null },
}

function formatMoney(value: number) {
  return `${value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} €`
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, { day: '2-digit', month: '2-digit', year: 'numeric' })
}

export default function AlertsIndex({ alerts, orders }: AlertsPageProps) {
  const { canWrite } = usePermissions()
  const [filter, setFilter] = useState<'all' | Alert['severity']>('all')
  const [poOpen, setPoOpen] = useState(false)
  const [detailPartId, setDetailPartId] = useState<number | null>(null)

  const filtered = useMemo(() => {
    if (filter === 'all') return alerts
    return alerts.filter((a) => a.severity === filter)
  }, [alerts, filter])

  const tabs = useMemo(() => {
    const counts = { all: alerts.length, critical: 0, low: 0 }
    alerts.forEach((a) => { counts[a.severity] += 1 })
    return [
      { value: 'all' as const, label: 'All', count: counts.all },
      { value: 'critical' as const, label: 'Critical', count: counts.critical },
      { value: 'low' as const, label: 'Low stock', count: counts.low },
    ]
  }, [alerts])

  const groups = useMemo(() => {
    const bySupplier = new Map<string, Alert[]>()
    alerts.filter((a) => a.supplier_name).forEach((a) => {
      const key = a.supplier_name as string
      if (!bySupplier.has(key)) bySupplier.set(key, [])
      bySupplier.get(key)!.push(a)
    })
    return Array.from(bySupplier.entries())
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([supplier, items]) => ({
        supplier,
        items,
        subtotal: items.reduce((sum, a) => sum + a.reorder_quantity * a.unit_price, 0),
      }))
  }, [alerts])

  const poTotal = groups.reduce((sum, g) => sum + g.subtotal, 0)
  const poLineCount = groups.reduce((sum, g) => sum + g.items.length, 0)
  const unassignedCount = alerts.length - poLineCount

  const stats = useMemo(() => {
    const critical = alerts.filter((a) => a.severity === 'critical').length
    const low = alerts.filter((a) => a.severity === 'low').length
    return [
      { label: 'Active alerts', value: String(alerts.length), className: '' },
      { label: 'Critical', value: String(critical), className: 'text-red-600 dark:text-red-400' },
      { label: 'Low stock', value: String(low), className: 'text-amber-600 dark:text-amber-400' },
      { label: 'To order', value: String(alerts.length), className: '' },
    ]
  }, [alerts])

  const printPo = () => {
    const rows = groups.map((g) => html`
      <h3 style="margin:18px 0 6px;font-size:14px;">${g.supplier} — ${formatMoney(g.subtotal)}</h3>
      <table style="width:100%;border-collapse:collapse;font-size:12px;margin-bottom:8px;">
        <thead><tr style="text-align:left;border-bottom:1px solid #ccc;">
          <th style="padding:4px 8px;">Reference</th><th style="padding:4px 8px;">Name</th>
          <th style="padding:4px 8px;text-align:right;">Qty</th><th style="padding:4px 8px;text-align:right;">Unit price</th>
          <th style="padding:4px 8px;text-align:right;">Total</th>
        </tr></thead>
        <tbody>${g.items.map((it) => html`
          <tr style="border-bottom:1px solid #eee;">
            <td style="padding:4px 8px;font-family:monospace;">${it.reference}</td>
            <td style="padding:4px 8px;">${it.name}</td>
            <td style="padding:4px 8px;text-align:right;">+${it.reorder_quantity}</td>
            <td style="padding:4px 8px;text-align:right;">${formatMoney(it.unit_price)}</td>
            <td style="padding:4px 8px;text-align:right;">${formatMoney(it.reorder_quantity * it.unit_price)}</td>
          </tr>`)}</tbody>
      </table>`)

    printDocument(
      'Purchase order',
      html`
        <h1 style="font-size:20px;margin:0 0 4px;">Restock purchase order</h1>
        <p style="color:#666;font-size:12px;margin:0 0 20px;">Makerstorage · Generated ${new Date().toLocaleDateString()}</p>
        ${rows}
        <p style="margin-top:16px;font-size:14px;font-weight:bold;">Estimated total: ${formatMoney(poTotal)}</p>`,
      'font-family:Arial,sans-serif;padding:32px;color:#111;',
    )
  }

  const submitPurchaseOrders = () => {
    router.post('/alerts/purchase_orders', {}, {
      preserveScroll: true,
      onSuccess: () => setPoOpen(false),
    })
  }

  const orderSingle = (alert: Alert) => {
    router.post('/alerts/purchase_orders', { part_id: alert.id }, { preserveScroll: true })
  }

  const advanceOrder = (order: Order) => {
    router.patch(`/alerts/orders/${order.id}/advance`, {}, { preserveScroll: true })
  }

  return (
    <AppLayout
      header={
        <PageHeader title="Alerts" subtitle="References under their minimum threshold to restock">
          {canWrite && groups.length > 0 && (
            <Button size="sm" onClick={() => setPoOpen(true)}>
              <FileText className="size-4" />
              Generate Purchase Order
            </Button>
          )}
        </PageHeader>
      }
    >
      <Head title="Alerts" />

      <div className="space-y-6">
        <FlashMessages />

        {/* Stats */}
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          {stats.map((stat) => (
            <Card key={stat.label}>
              <CardContent>
                <div className="text-sm text-muted-foreground">{stat.label}</div>
                <div className={`mt-1 font-mono text-2xl font-bold ${stat.className}`}>{stat.value}</div>
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Filter tabs */}
        <div className="flex flex-wrap items-center gap-2">
          {tabs.map((tab) => (
            <Button
              key={tab.value}
              variant="ghost"
              onClick={() => setFilter(tab.value)}
              className={`h-8 gap-1.5 border px-3 ${
                filter === tab.value
                  ? 'border-foreground bg-foreground text-background hover:bg-foreground/90 hover:text-background dark:hover:bg-foreground/90'
                  : 'border-border bg-background'
              }`}
            >
              {tab.label}
              <span className="font-mono opacity-60">{tab.count}</span>
            </Button>
          ))}
        </div>

        {/* Alert rows */}
        {filtered.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-2 py-10 text-center">
              <div className="flex size-11 items-center justify-center rounded-xl bg-emerald-100 text-emerald-600 dark:bg-emerald-950 dark:text-emerald-400">
                <CheckCircle2 className="size-[22px]" />
              </div>
              <p className="font-semibold">No alerts</p>
              <p className="text-sm text-muted-foreground">All stock in this category is above threshold.</p>
            </CardContent>
          </Card>
        ) : (
          <div className="flex flex-col gap-2.5">
            {filtered.map((alert) => (
              <Card key={alert.id} className={`flex-row items-center gap-3.5 border-l-[3px] py-3.5 pr-4 pl-4 ${SEVERITY_META[alert.severity].border}`}>
                <div className={`flex size-[34px] shrink-0 items-center justify-center rounded-[9px] ${SEVERITY_META[alert.severity].className}`}>
                  <AlertTriangle className="size-[17px]" />
                </div>
                <div className="min-w-[120px] flex-1">
                  <div className="flex items-center gap-2">
                    <span className="truncate font-mono text-sm font-semibold">{alert.reference}</span>
                    <Badge className={SEVERITY_META[alert.severity].className} variant="outline">
                      {SEVERITY_META[alert.severity].label}
                    </Badge>
                  </div>
                  <div className="truncate text-sm text-muted-foreground">{alert.name}</div>
                </div>
                <div className="min-w-0 shrink text-right text-xs text-muted-foreground">
                  <div className="truncate">Stock {alert.quantity} / threshold {alert.min_stock_threshold} · {alert.supplier_name || 'No supplier'}</div>
                  <div className="truncate font-mono">{alert.location_name || 'No location'}</div>
                </div>
                <div className="shrink-0 text-right">
                  <div className="text-xs text-muted-foreground">Suggested reorder</div>
                  <div className="font-mono text-base font-bold text-emerald-600 dark:text-emerald-400">+{alert.reorder_quantity}</div>
                </div>
                <Button variant="outline" size="sm" onClick={() => setDetailPartId(alert.id)}>
                  View
                </Button>
                {canWrite && (
                  <Button
                    size="sm"
                    disabled={!alert.supplier_name}
                    title={alert.supplier_name ? undefined : 'No preferred supplier to order from'}
                    onClick={() => orderSingle(alert)}
                  >
                    Order
                  </Button>
                )}
              </Card>
            ))}
          </div>
        )}

        {/* Orders in progress */}
        {orders.length > 0 && (
          <div>
            <h2 className="mb-2 text-sm font-semibold">Orders in progress</h2>
            <Card className="gap-0 overflow-hidden py-0 divide-y">
              {orders.map((order) => (
                <div key={order.id} className="flex items-center gap-3 px-4 py-3 text-sm">
                  <span className="shrink-0 font-mono font-semibold">{order.reference}</span>
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-medium">{order.supplier_name}</div>
                    <div className="text-xs text-muted-foreground">
                      {order.ordered_at ? formatDate(order.ordered_at) : '-'} · {order.line_count} reference{order.line_count !== 1 ? 's' : ''}
                    </div>
                  </div>
                  <Badge className={ORDER_STATUS_META[order.status].className} variant="outline">
                    {ORDER_STATUS_META[order.status].label}
                  </Badge>
                  <span className="w-20 shrink-0 text-right font-mono font-semibold">{formatMoney(order.total_amount)}</span>
                  {canWrite && ORDER_STATUS_META[order.status].next && (
                    <Button variant="outline" size="sm" onClick={() => advanceOrder(order)}>
                      {ORDER_STATUS_META[order.status].next}
                    </Button>
                  )}
                </div>
              ))}
            </Card>
          </div>
        )}
      </div>

      {/* Purchase order modal */}
      <Dialog open={poOpen} onOpenChange={setPoOpen}>
        <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-xl">
          <DialogHeader>
            <DialogTitle>Restock purchase order</DialogTitle>
            <DialogDescription>
              {poLineCount} reference{poLineCount !== 1 ? 's' : ''} below threshold, grouped across {groups.length} supplier{groups.length !== 1 ? 's' : ''}.
              Quantities are calculated to reach target stock.
              {unassignedCount > 0 && ` ${unassignedCount} alert${unassignedCount !== 1 ? 's have' : ' has'} no preferred supplier and will be skipped.`}
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4">
            {groups.map((group) => (
              <div key={group.supplier} className="overflow-hidden rounded-lg border">
                <div className="flex items-center justify-between gap-3 border-b bg-muted px-3.5 py-2.5">
                  <div>
                    <div className="text-sm font-semibold">{group.supplier}</div>
                    <div className="text-xs text-muted-foreground">{group.items.length} line{group.items.length !== 1 ? 's' : ''}</div>
                  </div>
                  <div className="text-right">
                    <div className="text-xs text-muted-foreground">Subtotal</div>
                    <div className="font-mono font-semibold">{formatMoney(group.subtotal)}</div>
                  </div>
                </div>
                <table className="w-full text-xs">
                  <thead>
                    <tr className="text-left text-muted-foreground">
                      <th className="px-3.5 py-1.5 font-medium">Reference</th>
                      <th className="px-2 py-1.5 text-right font-medium">Qty</th>
                      <th className="px-2 py-1.5 text-right font-medium">Unit price</th>
                      <th className="px-3.5 py-1.5 text-right font-medium">Total</th>
                    </tr>
                  </thead>
                  <tbody>
                    {group.items.map((item) => (
                      <tr key={item.id} className="border-t">
                        <td className="px-3.5 py-2">
                          <div className="font-mono font-semibold">{item.reference}</div>
                          <div className="max-w-[200px] truncate text-muted-foreground">{item.name}</div>
                        </td>
                        <td className="px-2 py-2 text-right font-mono font-semibold text-emerald-600 dark:text-emerald-400">+{item.reorder_quantity}</td>
                        <td className="px-2 py-2 text-right font-mono text-muted-foreground">{formatMoney(item.unit_price)}</td>
                        <td className="px-3.5 py-2 text-right font-mono">{formatMoney(item.reorder_quantity * item.unit_price)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ))}
          </div>
          <DialogFooter className="items-center sm:justify-between">
            <div>
              <div className="text-xs text-muted-foreground">Estimated total</div>
              <div className="text-lg font-bold font-mono">{formatMoney(poTotal)}</div>
            </div>
            <div className="flex gap-2">
              <Button variant="outline" onClick={printPo}>
                <Printer className="size-4" />
                Export PDF
              </Button>
              <Button onClick={submitPurchaseOrders}>Create Purchase Orders</Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Part detail sidebar */}
      <PartDetailSheet
        partId={detailPartId}
        open={detailPartId !== null}
        onOpenChange={(open) => !open && setDetailPartId(null)}
      />
    </AppLayout>
  )
}
