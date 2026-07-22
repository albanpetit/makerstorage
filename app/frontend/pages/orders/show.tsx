import { Head, Link, router, useForm } from '@inertiajs/react'
import { useMemo, useState } from 'react'
import { ArrowLeft, Plus, Trash2, Truck, PackageCheck, Ban, Pencil, ClipboardList, ShoppingCart } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Combobox, type ComboboxOption } from '@/components/ui/combobox'
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
import { SupplierLookup, type LookupResult } from '@/components/supplier-lookup'
import { ORDER_STATUS_META, formatMoney } from './helpers'

interface OrderLine {
  id: number
  quantity: number
  unit_price: number | null
  subtotal: number | null
  part: { id: number; reference: string; name: string }
}

interface Order {
  id: number
  reference: string | null
  status: keyof typeof ORDER_STATUS_META
  editable: boolean
  supplier: { id: number; name: string }
  ordered_at: string | null
  expected_delivery: string | null
  notes: string | null
  total_amount: number
  lines: OrderLine[]
}

interface SupplierOption {
  id: number
  name: string
}

interface PartOption {
  id: number
  reference: string
  name: string
  mpn: string | null
  sku: string | null
}

interface CategoryOption {
  id: number
  name: string
}

interface ProjectOption {
  id: number
  name: string
  reference: string | null
  line_count: number
}

interface OrderShowProps {
  order: Order
  suppliers: SupplierOption[]
  parts: PartOption[]
  categories: CategoryOption[]
  catalog_enabled: boolean
  projects: ProjectOption[]
  mouser_cart_enabled: boolean
}

const ADVANCE_LABEL: Partial<Record<Order['status'], { label: string; icon: typeof Truck }>> = {
  pending: { label: 'Mark as shipped', icon: Truck },
  shipped: { label: 'Mark as received', icon: PackageCheck },
}

export default function OrderShow({ order, suppliers, parts, categories, catalog_enabled, projects, mouser_cart_enabled }: OrderShowProps) {
  const { canWrite } = usePermissions()
  const [addOpen, setAddOpen] = useState(false)
  const [importOpen, setImportOpen] = useState(false)
  const [importProject, setImportProject] = useState('')
  const [importMode, setImportMode] = useState<'full' | 'shortfall'>('full')
  const [addMode, setAddMode] = useState<'inventory' | 'catalog'>('inventory')
  const [applied, setApplied] = useState<LookupResult | null>(null)
  const [catalogCategory, setCatalogCategory] = useState('')
  const [catalogQty, setCatalogQty] = useState('1')
  const [catalogSubmitting, setCatalogSubmitting] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [receiveOpen, setReceiveOpen] = useState(false)

  const meta = ORDER_STATUS_META[order.status]
  const advance = ADVANCE_LABEL[order.status]

  const partOptions = useMemo<ComboboxOption[]>(
    () => parts.map((p) => ({ value: String(p.id), label: `${p.reference} — ${p.name}` })),
    [parts]
  )

  const addForm = useForm({ order_line: { part_id: '', quantity: '1', unit_price: '' } })
  const editForm = useForm({
    order: {
      supplier_id: String(order.supplier.id),
      reference: order.reference ?? '',
      ordered_at: order.ordered_at ?? '',
      expected_delivery: order.expected_delivery ?? '',
      notes: order.notes ?? '',
    },
  })

  const openAdd = () => {
    addForm.reset()
    addForm.clearErrors()
    setApplied(null)
    setCatalogCategory('')
    setCatalogQty('1')
    setAddMode('inventory')
    setAddOpen(true)
  }

  const submitAdd = (e: React.FormEvent) => {
    e.preventDefault()
    addForm.post(`/orders/${order.id}/order_lines`, {
      preserveScroll: true,
      onSuccess: () => {
        addForm.reset()
        setAddOpen(false)
      },
    })
  }

  const submitCatalog = (e: React.FormEvent) => {
    e.preventDefault()
    if (!applied || !catalogCategory) return
    setCatalogSubmitting(true)
    router.post(
      `/orders/${order.id}/order_lines/catalog`,
      {
        order_line: { quantity: catalogQty },
        category_id: catalogCategory,
        image_url: applied.image_url,
        supplier_sku: applied.supplier_sku,
        product_url: applied.product_url,
        part: {
          name: applied.name,
          mpn: applied.mpn,
          manufacturer: applied.manufacturer,
          description: applied.description,
          value: applied.value,
          tolerance: applied.tolerance,
          voltage_rating: applied.voltage_rating,
          power_rating: applied.power_rating,
          package_type: applied.package_type,
          unit_price: applied.unit_price,
          rohs_compliant: applied.rohs_compliant,
        },
      },
      {
        preserveScroll: true,
        onSuccess: () => setAddOpen(false),
        onFinish: () => setCatalogSubmitting(false),
      }
    )
  }

  const submitEdit = (e: React.FormEvent) => {
    e.preventDefault()
    editForm.patch(`/orders/${order.id}`, {
      preserveScroll: true,
      onSuccess: () => setEditOpen(false),
    })
  }

  const updateLine = (line: OrderLine, data: Record<string, string | number>) => {
    router.patch(`/orders/${order.id}/order_lines/${line.id}`, { order_line: data }, { preserveScroll: true })
  }

  const changeQuantity = (line: OrderLine, raw: string) => {
    const quantity = Number(raw)
    if (!Number.isInteger(quantity) || quantity < 1 || quantity === line.quantity) return
    updateLine(line, { quantity })
  }

  const changePrice = (line: OrderLine, raw: string) => {
    const value = raw.trim()
    const price = Number(value)
    if (value === '' || Number.isNaN(price) || price < 0 || price === line.unit_price) return
    updateLine(line, { unit_price: price })
  }

  const submitImport = (e: React.FormEvent) => {
    e.preventDefault()
    if (!importProject) return
    router.post(
      `/orders/${order.id}/import_project`,
      { project_id: importProject, mode: importMode },
      {
        preserveScroll: true,
        onSuccess: () => {
          setImportOpen(false)
          setImportProject('')
        },
      }
    )
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
                  Edit
                </Button>
              )}
              {mouser_cart_enabled && order.lines.length > 0 && (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => router.post(`/orders/${order.id}/push_to_cart`, {}, { preserveScroll: true })}
                >
                  <ShoppingCart className="size-4" />
                  Send to Mouser cart
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
                  Cancel
                </Button>
              )}
              <Button size="sm" variant="outline" onClick={() => setDeleteOpen(true)}>
                <Trash2 className="size-4" />
                Delete
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
          All orders
        </Link>

        {/* Summary */}
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <SummaryCard label="Status" value={<Badge variant="outline" className={meta.className}>{meta.label}</Badge>} />
          <SummaryCard label="Lines" value={order.lines.length} />
          <SummaryCard label="Total" value={formatMoney(order.total_amount)} />
          <SummaryCard
            label="Expected"
            value={order.expected_delivery ? new Date(order.expected_delivery).toLocaleDateString() : '—'}
          />
        </div>

        {order.notes && (
          <Card>
            <CardContent className="whitespace-pre-wrap text-sm text-muted-foreground">{order.notes}</CardContent>
          </Card>
        )}

        {/* Lines */}
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold">Components</h2>
          {canWrite && order.editable && (
            <div className="flex gap-2">
              {projects.length > 0 && (
                <Button size="sm" variant="outline" onClick={() => setImportOpen(true)}>
                  <ClipboardList className="size-4" />
                  Import from project
                </Button>
              )}
              <Button size="sm" variant="outline" onClick={openAdd}>
                <Plus className="size-4" />
                Add component
              </Button>
            </div>
          )}
        </div>

        <Card className="overflow-hidden py-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Component</TableHead>
                <TableHead className="text-right">Quantity</TableHead>
                <TableHead className="text-right">Unit price</TableHead>
                <TableHead className="text-right">Subtotal</TableHead>
                {canWrite && order.editable && <TableHead className="w-10" />}
              </TableRow>
            </TableHeader>
            <TableBody>
              {order.lines.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={5} className="py-10 text-center text-sm text-muted-foreground">
                    No components yet. Add one from your inventory.
                  </TableCell>
                </TableRow>
              ) : (
                order.lines.map((line) => (
                  <TableRow key={line.id}>
                    <TableCell>
                      <Link href={`/parts?highlight=${line.part.id}`} className="font-medium hover:underline">
                        {line.part.reference}
                      </Link>
                      <div className="max-w-[280px] truncate text-xs text-muted-foreground">{line.part.name}</div>
                    </TableCell>
                    <TableCell className="text-right">
                      {canWrite && order.editable ? (
                        <Input
                          type="number"
                          min={1}
                          defaultValue={line.quantity}
                          className="ml-auto h-8 w-20 text-right font-mono"
                          onBlur={(e) => changeQuantity(line, e.target.value)}
                        />
                      ) : (
                        <span className="font-mono">{line.quantity}</span>
                      )}
                    </TableCell>
                    <TableCell className="text-right">
                      {canWrite && order.editable ? (
                        <Input
                          type="number"
                          min={0}
                          step="0.01"
                          defaultValue={line.unit_price ?? ''}
                          placeholder="—"
                          className="ml-auto h-8 w-24 text-right font-mono"
                          onBlur={(e) => changePrice(line, e.target.value)}
                        />
                      ) : (
                        <span className="font-mono">{line.unit_price != null ? formatMoney(line.unit_price) : '—'}</span>
                      )}
                    </TableCell>
                    <TableCell className="text-right font-mono">
                      {line.subtotal != null ? formatMoney(line.subtotal) : '—'}
                    </TableCell>
                    {canWrite && order.editable && (
                      <TableCell>
                        <Button
                          variant="ghost"
                          size="icon-sm"
                          aria-label="Remove line"
                          onClick={() => router.delete(`/orders/${order.id}/order_lines/${line.id}`, { preserveScroll: true })}
                        >
                          <Trash2 className="size-4 text-muted-foreground" />
                        </Button>
                      </TableCell>
                    )}
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </Card>

        <div className="flex justify-end">
          <div className="flex w-64 items-center justify-between rounded-lg border px-4 py-2">
            <span className="text-sm text-muted-foreground">Total</span>
            <span className="font-mono text-lg font-bold">{formatMoney(order.total_amount)}</span>
          </div>
        </div>
      </div>

      {/* Add component dialog */}
      <Dialog open={addOpen} onOpenChange={setAddOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Add component</DialogTitle>
            <DialogDescription>
              Pick a part from your inventory, or search a supplier catalog to add a new one.
            </DialogDescription>
          </DialogHeader>

          {catalog_enabled && (
            <div className="grid grid-cols-2 gap-1 rounded-lg bg-muted p-1">
              <Button
                type="button"
                size="sm"
                variant={addMode === 'inventory' ? 'default' : 'ghost'}
                onClick={() => setAddMode('inventory')}
              >
                From inventory
              </Button>
              <Button
                type="button"
                size="sm"
                variant={addMode === 'catalog' ? 'default' : 'ghost'}
                onClick={() => setAddMode('catalog')}
              >
                Search catalog
              </Button>
            </div>
          )}

          {addMode === 'inventory' ? (
            <form onSubmit={submitAdd}>
              <div className="space-y-4 py-4">
                <div className="space-y-2">
                  <Label>Part</Label>
                  <Combobox
                    options={partOptions}
                    value={addForm.data.order_line.part_id}
                    onValueChange={(value) => addForm.setData('order_line', { ...addForm.data.order_line, part_id: value })}
                    placeholder="Select a part"
                    searchPlaceholder="Search parts…"
                    className="w-full"
                  />
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-2">
                    <Label htmlFor="add-qty">Quantity</Label>
                    <Input
                      id="add-qty"
                      type="number"
                      min={1}
                      value={addForm.data.order_line.quantity}
                      onChange={(e) => addForm.setData('order_line', { ...addForm.data.order_line, quantity: e.target.value })}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="add-price">Unit price</Label>
                    <Input
                      id="add-price"
                      type="number"
                      min={0}
                      step="0.01"
                      placeholder="Auto"
                      value={addForm.data.order_line.unit_price}
                      onChange={(e) => addForm.setData('order_line', { ...addForm.data.order_line, unit_price: e.target.value })}
                    />
                  </div>
                </div>
                <p className="text-xs text-muted-foreground">Leave the price blank to use the supplier or part price.</p>
              </div>

              <DialogFooter>
                <Button type="button" variant="outline" onClick={() => setAddOpen(false)}>
                  Cancel
                </Button>
                <Button type="submit" disabled={addForm.processing || !addForm.data.order_line.part_id}>
                  Add to order
                </Button>
              </DialogFooter>
            </form>
          ) : (
            <form onSubmit={submitCatalog}>
              <div className="space-y-4 py-4">
                {applied ? (
                  <div className="space-y-4">
                    <div className="rounded-lg border p-3">
                      <div className="flex items-center gap-2">
                        <span className="truncate font-medium">{applied.mpn ?? applied.name}</span>
                        {applied.manufacturer && (
                          <Badge variant="secondary" className="shrink-0 text-[10px]">{applied.manufacturer}</Badge>
                        )}
                        <Button
                          type="button"
                          variant="ghost"
                          size="sm"
                          className="ml-auto h-7"
                          onClick={() => setApplied(null)}
                        >
                          Change
                        </Button>
                      </div>
                      {applied.description && (
                        <p className="mt-1 truncate text-xs text-muted-foreground">{applied.description}</p>
                      )}
                    </div>

                    <div className="space-y-2">
                      <Label>Category</Label>
                      <Select value={catalogCategory} onValueChange={setCatalogCategory}>
                        <SelectTrigger>
                          <SelectValue placeholder="Select a category" />
                        </SelectTrigger>
                        <SelectContent>
                          {categories.map((c) => (
                            <SelectItem key={c.id} value={String(c.id)}>{c.name}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <p className="text-xs text-muted-foreground">Required — the new part is created in your inventory.</p>
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="catalog-qty">Quantity</Label>
                      <Input
                        id="catalog-qty"
                        type="number"
                        min={1}
                        value={catalogQty}
                        onChange={(e) => setCatalogQty(e.target.value)}
                      />
                    </div>
                  </div>
                ) : (
                  <SupplierLookup onApply={setApplied} />
                )}
              </div>

              <DialogFooter>
                <Button type="button" variant="outline" onClick={() => setAddOpen(false)}>
                  Cancel
                </Button>
                <Button type="submit" disabled={!applied || !catalogCategory || catalogSubmitting}>
                  Create & add
                </Button>
              </DialogFooter>
            </form>
          )}
        </DialogContent>
      </Dialog>

      {/* Import from project dialog */}
      <Dialog open={importOpen} onOpenChange={setImportOpen}>
        <DialogContent className="sm:max-w-md">
          <form onSubmit={submitImport}>
            <DialogHeader>
              <DialogTitle>Import from project</DialogTitle>
              <DialogDescription>
                Add a project's matched BOM lines to this order. Unmatched lines are skipped.
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label>Project</Label>
                <Select value={importProject} onValueChange={setImportProject}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select a project" />
                  </SelectTrigger>
                  <SelectContent>
                    {projects.map((p) => (
                      <SelectItem key={p.id} value={String(p.id)}>
                        {p.name} ({p.line_count} line{p.line_count !== 1 ? 's' : ''})
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label>Quantities</Label>
                <Select value={importMode} onValueChange={(v) => setImportMode(v as 'full' | 'shortfall')}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="full">Full BOM quantities</SelectItem>
                    <SelectItem value="shortfall">Shortfall only (what stock can't cover)</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setImportOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={!importProject}>
                Import lines
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Edit details dialog */}
      <Dialog open={editOpen} onOpenChange={setEditOpen}>
        <DialogContent className="sm:max-w-md">
          <form onSubmit={submitEdit}>
            <DialogHeader>
              <DialogTitle>Edit order</DialogTitle>
              <DialogDescription>Update the supplier, reference, dates, and notes.</DialogDescription>
            </DialogHeader>

            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="edit-supplier">Supplier</Label>
                <Select
                  value={editForm.data.order.supplier_id}
                  onValueChange={(value) => editForm.setData('order', { ...editForm.data.order, supplier_id: value })}
                >
                  <SelectTrigger id="edit-supplier">
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
                <Label htmlFor="edit-reference">Reference</Label>
                <Input
                  id="edit-reference"
                  value={editForm.data.order.reference}
                  onChange={(e) => editForm.setData('order', { ...editForm.data.order, reference: e.target.value })}
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-2">
                  <Label htmlFor="edit-ordered">Ordered on</Label>
                  <Input
                    id="edit-ordered"
                    type="date"
                    value={editForm.data.order.ordered_at}
                    onChange={(e) => editForm.setData('order', { ...editForm.data.order, ordered_at: e.target.value })}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="edit-expected">Expected</Label>
                  <Input
                    id="edit-expected"
                    type="date"
                    value={editForm.data.order.expected_delivery}
                    onChange={(e) => editForm.setData('order', { ...editForm.data.order, expected_delivery: e.target.value })}
                  />
                </div>
              </div>
              <div className="space-y-2">
                <Label htmlFor="edit-notes">Notes</Label>
                <Textarea
                  id="edit-notes"
                  rows={3}
                  value={editForm.data.order.notes}
                  onChange={(e) => editForm.setData('order', { ...editForm.data.order, notes: e.target.value })}
                />
              </div>
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setEditOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={editForm.processing}>
                Save changes
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Receive confirmation (credits stock) */}
      <AlertDialog open={receiveOpen} onOpenChange={setReceiveOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Mark this order as received?</AlertDialogTitle>
            <AlertDialogDescription>
              This credits each line's quantity into its part's storage location as an incoming movement, and freezes the order.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                doAdvance()
                setReceiveOpen(false)
              }}
            >
              Receive
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Delete confirmation */}
      <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
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
                router.delete(`/orders/${order.id}`)
                setDeleteOpen(false)
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
