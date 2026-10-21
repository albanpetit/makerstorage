import { Head, Link, router } from '@inertiajs/react'
import { useState } from 'react'
import { ArrowLeft, Plus, Trash2, Truck, PackageCheck, Ban, Pencil, ClipboardList, ShoppingCart, Boxes } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { AddLineDialog } from '@/components/orders/add-line-dialog'
import { AllocationDialog } from '@/components/orders/allocation-dialog'
import { BulkZoneDialog } from '@/components/orders/bulk-zone-dialog'
import { EditOrderDialog } from '@/components/orders/edit-order-dialog'
import { ImportProjectDialog } from '@/components/orders/import-project-dialog'
import { OrderLinesTable } from '@/components/orders/order-lines-table'
import type { Order, OrderLine, OrderShowProps } from '@/components/orders/types'
import { ORDER_STATUS_META, formatMoney } from './helpers'
import { t, intlLocale } from '@/lib/i18n'

const ADVANCE_LABEL: Partial<Record<Order['status'], { label: string; icon: typeof Truck }>> = {
  pending: { get label() { return t('Mark as shipped') }, icon: Truck },
  shipped: { get label() { return t('Mark as received') }, icon: PackageCheck },
}

export default function OrderShow({ order, suppliers, parts, categories, catalog_enabled, projects, mouser_cart_enabled, storage_locations }: OrderShowProps) {
  const { canWrite } = usePermissions()
  const [addOpen, setAddOpen] = useState(false)
  const [allocLine, setAllocLine] = useState<OrderLine | null>(null)
  const [bulkZoneOpen, setBulkZoneOpen] = useState(false)
  const [importOpen, setImportOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [receiveOpen, setReceiveOpen] = useState(false)
  // Bumped each time a dialog that starts blank is opened, so it remounts with
  // fresh state.
  const [dialogKey, setDialogKey] = useState(0)

  const meta = ORDER_STATUS_META[order.status]
  const advance = ADVANCE_LABEL[order.status]

  const openAdd = () => {
    setDialogKey((k) => k + 1)
    setAddOpen(true)
  }

  const openAllocEditor = (line: OrderLine) => {
    setDialogKey((k) => k + 1)
    setAllocLine(line)
  }

  const doAdvance = () => router.patch(`/orders/${order.id}/advance`, {}, { preserveScroll: true })
  const cancelOrder = () =>
    router.patch(`/orders/${order.id}`, { order: { status: 'cancelled' } }, { preserveScroll: true })

  return (
    <AppLayout
      header={
        <PageHeader title={order.reference || `Order #${order.id}`} subtitle={order.supplier.name}>
          {canWrite && (
            <div className="flex flex-wrap gap-2">
              {order.editable && (
                <Button size="sm" variant="outline" onClick={() => setEditOpen(true)}>
                  <Pencil className="size-4" />
                  {t('Edit')}
                </Button>
              )}
              {mouser_cart_enabled && order.lines.length > 0 && (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => router.post(`/orders/${order.id}/push_to_cart`, {}, { preserveScroll: true })}
                >
                  <ShoppingCart className="size-4" />
                  {t('Send to Mouser cart')}
                </Button>
              )}
              {advance && (
                <Button
                  size="sm"
                  onClick={() => (order.status === 'shipped' ? setReceiveOpen(true) : doAdvance())}
                >
                  <advance.icon className="size-4" />
                  {advance.label}
                </Button>
              )}
              {order.editable && (
                <Button size="sm" variant="outline" onClick={cancelOrder}>
                  <Ban className="size-4" />
                  {t('Cancel')}
                </Button>
              )}
              <Button size="sm" variant="outline" onClick={() => setDeleteOpen(true)}>
                <Trash2 className="size-4" />
                {t('Delete')}
              </Button>
            </div>
          )}
        </PageHeader>
      }
    >
      <Head title={order.reference || `Order #${order.id}`} />

      <div className="space-y-6">
        <FlashMessages />

        <Link href="/orders" className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground">
          <ArrowLeft className="size-4" />
          {t('All orders')}
        </Link>

        {/* Summary */}
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <SummaryCard label={t('Status')} value={<Badge variant="outline" className={meta.className}>{meta.label}</Badge>} />
          <SummaryCard label={t('Lines')} value={order.lines.length} />
          <SummaryCard label={t('Total')} value={formatMoney(order.total_amount)} />
          <SummaryCard
            label={t('Expected')}
            value={order.expected_delivery ? new Date(order.expected_delivery).toLocaleDateString(intlLocale()) : '—'}
          />
        </div>

        {order.notes && (
          <Card>
            <CardContent className="whitespace-pre-wrap text-sm text-muted-foreground">{order.notes}</CardContent>
          </Card>
        )}

        {/* Lines */}
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold">{t('Components')}</h2>
          {canWrite && order.editable && (
            <div className="flex flex-wrap gap-2">
              {order.lines.length > 0 && storage_locations.length > 0 && (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    setDialogKey((k) => k + 1)
                    setBulkZoneOpen(true)
                  }}
                >
                  <Boxes className="size-4" />
                  {t('Set storage zone')}
                </Button>
              )}
              {projects.length > 0 && (
                <Button size="sm" variant="outline" onClick={() => setImportOpen(true)}>
                  <ClipboardList className="size-4" />
                  {t('Import from project')}
                </Button>
              )}
              <Button size="sm" variant="outline" onClick={openAdd}>
                <Plus className="size-4" />
                {t('Add component')}
              </Button>
            </div>
          )}
        </div>

        <OrderLinesTable order={order} onEditAllocation={openAllocEditor} />

        <div className="flex justify-end">
          <div className="flex w-64 items-center justify-between rounded-lg border px-4 py-2">
            <span className="text-sm text-muted-foreground">{t('Total')}</span>
            <span className="font-mono text-lg font-bold">{formatMoney(order.total_amount)}</span>
          </div>
        </div>
      </div>

      <AddLineDialog
        key={`add-${dialogKey}`}
        open={addOpen}
        onOpenChange={setAddOpen}
        order={order}
        parts={parts}
        categories={categories}
        catalogEnabled={catalog_enabled}
      />

      <AllocationDialog
        key={`alloc-${dialogKey}`}
        order={order}
        allocLine={allocLine}
        onClose={() => setAllocLine(null)}
        storageLocations={storage_locations}
      />

      <BulkZoneDialog
        key={`zone-${dialogKey}`}
        open={bulkZoneOpen}
        onOpenChange={setBulkZoneOpen}
        order={order}
        storageLocations={storage_locations}
      />

      <ImportProjectDialog open={importOpen} onOpenChange={setImportOpen} order={order} projects={projects} />

      <EditOrderDialog open={editOpen} onOpenChange={setEditOpen} order={order} suppliers={suppliers} />

      {/* Receive confirmation (credits stock) */}
      <AlertDialog open={receiveOpen} onOpenChange={setReceiveOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('Mark this order as received?')}</AlertDialogTitle>
            <AlertDialogDescription>
              {t('This credits each line into stock as incoming movements — into the zones you configured, or the part\'s existing location when none is set — and freezes the order.')}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('Cancel')}</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                doAdvance()
                setReceiveOpen(false)
              }}
            >
              {t('Receive')}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Delete confirmation */}
      <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('Delete this order?')}</AlertDialogTitle>
            <AlertDialogDescription>
              {t('This removes the order and its lines. Stock movements already recorded on receipt are not affected.')}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('Cancel')}</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                router.delete(`/orders/${order.id}`)
                setDeleteOpen(false)
              }}
            >
              {t('Delete')}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </AppLayout>
  )
}

function SummaryCard({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <Card>
      <CardContent>
        <div className="text-sm text-muted-foreground">{label}</div>
        <div className="mt-1 text-2xl font-bold">{value}</div>
      </CardContent>
    </Card>
  )
}
