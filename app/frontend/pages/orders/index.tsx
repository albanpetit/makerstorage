import { Head, Link, router, useForm } from '@inertiajs/react'
import { useState } from 'react'
import { ShoppingCart, Plus, Trash2, Download } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { ReadOnlyBadge } from '@/components/read-only-badge'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
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
import { ORDER_STATUS_META, formatMoney, formatDate } from './helpers'

interface OrderSummary {
  id: number
  reference: string | null
  supplier_name: string
  status: keyof typeof ORDER_STATUS_META
  ordered_at: string | null
  expected_delivery: string | null
  total_amount: number
  line_count: number
  created_at: string
}

interface SupplierOption {
  id: number
  name: string
}

interface OrdersPageProps {
  orders: OrderSummary[]
  suppliers: SupplierOption[]
  mouser_order_enabled: boolean
  digikey_order_enabled: boolean
}

export default function OrdersIndex({ orders, suppliers, mouser_order_enabled, digikey_order_enabled }: OrdersPageProps) {
  const { canWrite } = usePermissions()
  const [open, setOpen] = useState(false)
  const [importOpen, setImportOpen] = useState(false)
  const [deleteId, setDeleteId] = useState<number | null>(null)

  const importProviders = [
    ...(mouser_order_enabled ? [{ value: 'mouser', label: 'Mouser' }] : []),
    ...(digikey_order_enabled ? [{ value: 'digikey', label: 'DigiKey' }] : []),
  ]

  const form = useForm({ order: { supplier_id: '', expected_delivery: '' } })
  const importForm = useForm({ order_number: '', provider: importProviders[0]?.value ?? 'mouser' })

  const openDialog = () => {
    form.reset()
    form.clearErrors()
    setOpen(true)
  }

  const submit = (e: React.FormEvent) => {
    e.preventDefault()
    form.post('/orders', {
      onSuccess: () => setOpen(false),
    })
  }

  const submitImport = (e: React.FormEvent) => {
    e.preventDefault()
    importForm.post('/orders/import_supplier_order', {
      onSuccess: () => {
        importForm.reset()
        setImportOpen(false)
      },
    })
  }

  return (
    <AppLayout
      header={
        <PageHeader title="Orders" subtitle="Create supplier purchase orders and track them to delivery">
          {canWrite ? (
            <div className="flex gap-2">
              {importProviders.length > 0 && (
                <Button size="sm" variant="outline" onClick={() => setImportOpen(true)}>
                  <Download className="size-4" />
                  Import order
                </Button>
              )}
              <Button size="sm" onClick={openDialog} disabled={suppliers.length === 0}>
                <Plus className="size-4" />
                New order
              </Button>
            </div>
          ) : (
            <ReadOnlyBadge />
          )}
        </PageHeader>
      }
    >
      <Head title="Orders" />

      <div className="space-y-6">
        <FlashMessages />

        {orders.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
              <div className="flex size-11 items-center justify-center rounded-xl bg-muted text-muted-foreground">
                <ShoppingCart className="size-[22px]" />
              </div>
              <p className="font-semibold">No orders yet</p>
              <p className="max-w-sm text-sm text-muted-foreground">
                Create an order for a supplier, then add components from your inventory, a catalog search, or a project BOM.
              </p>
            </CardContent>
          </Card>
        ) : (
          <Card className="overflow-hidden py-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Reference</TableHead>
                  <TableHead>Supplier</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Lines</TableHead>
                  <TableHead className="text-right">Total</TableHead>
                  <TableHead>Ordered</TableHead>
                  <TableHead className="w-10" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {orders.map((order) => {
                  const meta = ORDER_STATUS_META[order.status]
                  return (
                    <TableRow key={order.id} className="cursor-pointer" onClick={() => router.visit(`/orders/${order.id}`)}>
                      <TableCell className="font-mono text-xs font-medium">
                        <Link href={`/orders/${order.id}`} className="hover:underline" onClick={(e) => e.stopPropagation()}>
                          {order.reference || `#${order.id}`}
                        </Link>
                      </TableCell>
                      <TableCell>{order.supplier_name}</TableCell>
                      <TableCell>
                        <Badge variant="outline" className={meta.className}>{meta.label}</Badge>
                      </TableCell>
                      <TableCell className="text-right font-mono">{order.line_count}</TableCell>
                      <TableCell className="text-right font-mono">{formatMoney(order.total_amount)}</TableCell>
                      <TableCell className="text-xs text-muted-foreground">
                        {order.ordered_at ? formatDate(order.ordered_at) : '—'}
                      </TableCell>
                      <TableCell>
                        {canWrite && (
                          <Button
                            variant="ghost"
                            size="icon-sm"
                            aria-label="Delete order"
                            onClick={(e) => {
                              e.stopPropagation()
                              setDeleteId(order.id)
                            }}
                          >
                            <Trash2 className="size-4 text-muted-foreground" />
                          </Button>
                        )}
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </Card>
        )}
      </div>

      {/* New order dialog */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-md">
          <form onSubmit={submit}>
            <DialogHeader>
              <DialogTitle>New order</DialogTitle>
              <DialogDescription>
                Pick a supplier to start a draft order. A reference is generated automatically; you can add components next.
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="order-supplier">Supplier</Label>
                <Select
                  value={form.data.order.supplier_id}
                  onValueChange={(value) => form.setData('order', { ...form.data.order, supplier_id: value })}
                >
                  <SelectTrigger id="order-supplier" aria-invalid={!!form.errors['order.supplier_id']}>
                    <SelectValue placeholder="Select a supplier" />
                  </SelectTrigger>
                  <SelectContent>
                    {suppliers.map((supplier) => (
                      <SelectItem key={supplier.id} value={String(supplier.id)}>
                        {supplier.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label htmlFor="order-expected">Expected delivery</Label>
                <Input
                  id="order-expected"
                  type="date"
                  value={form.data.order.expected_delivery}
                  onChange={(e) => form.setData('order', { ...form.data.order, expected_delivery: e.target.value })}
                />
                <p className="text-xs text-muted-foreground">Optional.</p>
              </div>
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={form.processing || !form.data.order.supplier_id}>
                Create order
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Import Mouser order dialog */}
      <Dialog open={importOpen} onOpenChange={setImportOpen}>
        <DialogContent className="sm:max-w-md">
          <form onSubmit={submitImport}>
            <DialogHeader>
              <DialogTitle>Import a supplier order</DialogTitle>
              <DialogDescription>
                Pull a placed order's lines into a new order. Parts are matched to your inventory and created when missing.
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-4 py-4">
              {importProviders.length > 1 && (
                <div className="space-y-2">
                  <Label>Supplier</Label>
                  <Select value={importForm.data.provider} onValueChange={(v) => importForm.setData('provider', v)}>
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {importProviders.map((p) => (
                        <SelectItem key={p.value} value={p.value}>{p.label}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}

              <div className="space-y-2">
                <Label htmlFor="import-order-number">
                  {importForm.data.provider === 'digikey' ? 'Sales order number' : 'Web order number'}
                </Label>
                <Input
                  id="import-order-number"
                  value={importForm.data.order_number}
                  onChange={(e) => importForm.setData('order_number', e.target.value)}
                  placeholder="e.g. 12345678"
                  autoFocus
                />
              </div>
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setImportOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={importForm.processing || !importForm.data.order_number.trim()}>
                Import
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation */}
      <AlertDialog open={deleteId !== null} onOpenChange={(o) => !o && setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete this order?</AlertDialogTitle>
            <AlertDialogDescription>
              This removes the order and its lines. Stock movements already recorded on receipt are not affected.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (deleteId !== null) router.delete(`/orders/${deleteId}`, { preserveScroll: true })
                setDeleteId(null)
              }}
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </AppLayout>
  )
}
