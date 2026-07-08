import { Head, router, useForm } from '@inertiajs/react'
import { FormEvent, useMemo, useState } from 'react'
import { Plus, Mail, Truck, Package, Clock, Pencil, Trash2 } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetFooter,
} from '@/components/ui/sheet'
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

const AVATAR_COLORS = [
  'bg-amber-600', 'bg-blue-600', 'bg-red-600', 'bg-emerald-600', 'bg-purple-600', 'bg-cyan-600', 'bg-pink-600',
]

const PURCHASE_STATUS_META: Record<string, { label: string; className: string }> = {
  pending: { label: 'Pending', className: 'bg-muted text-muted-foreground' },
  shipped: { label: 'Shipped', className: 'bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-400' },
  received: { label: 'Received', className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
  cancelled: { label: 'Cancelled', className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
}

interface LinkedComponent {
  id: number
  reference: string
  name: string
  quantity: number
  low_stock: boolean
  unit_price: number | null
}

interface Order {
  id: number
  reference: string | null
  ordered_at: string | null
  status: string
  total_amount: number
}

interface Supplier {
  id: number
  name: string
  email: string | null
  phone: string | null
  website: string | null
  country: string | null
  city: string | null
  reference_count: number
  avg_lead_time_days: number | null
  stock_value: number
  last_order_at: string | null
  order_count: number
  components: LinkedComponent[]
  orders: Order[]
}

interface SuppliersPageProps {
  suppliers: Supplier[]
}

function initials(name: string) {
  const words = name.trim().split(/\s+/)
  return words.length === 1
    ? words[0].slice(0, 2).toUpperCase()
    : (words[0][0] + words[1][0]).toUpperCase()
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, { day: '2-digit', month: '2-digit', year: 'numeric' })
}

function formatMoney(value: number) {
  return `${value.toLocaleString(undefined, { maximumFractionDigits: 0 })} €`
}

interface SupplierFormData {
  supplier: {
    name: string
    email: string
    phone: string
    website: string
    country: string
    city: string
  }
}

const EMPTY_FORM: SupplierFormData['supplier'] = {
  name: '', email: '', phone: '', website: '', country: '', city: '',
}

export default function SuppliersIndex({ suppliers }: SuppliersPageProps) {
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [newOpen, setNewOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)

  const selected = selectedId != null ? suppliers.find((s) => s.id === selectedId) : undefined

  const newForm = useForm<SupplierFormData>({ supplier: EMPTY_FORM })
  const editForm = useForm<SupplierFormData>({ supplier: EMPTY_FORM })

  const openNewDialog = () => {
    newForm.reset()
    newForm.clearErrors()
    setNewOpen(true)
  }

  const submitNew = (e: FormEvent) => {
    e.preventDefault()
    newForm.post('/suppliers', {
      preserveScroll: true,
      onSuccess: () => setNewOpen(false),
    })
  }

  const openEditDialog = () => {
    if (!selected) return
    editForm.clearErrors()
    editForm.setData('supplier', {
      name: selected.name,
      email: selected.email || '',
      phone: selected.phone || '',
      website: selected.website || '',
      country: selected.country || '',
      city: selected.city || '',
    })
    setEditOpen(true)
  }

  const submitEdit = (e: FormEvent) => {
    e.preventDefault()
    if (!selected) return
    editForm.patch(`/suppliers/${selected.id}`, {
      preserveScroll: true,
      onSuccess: () => setEditOpen(false),
    })
  }

  const confirmDelete = () => {
    if (!selected) return
    router.delete(`/suppliers/${selected.id}`, {
      preserveScroll: true,
      onSuccess: () => {
        setDeleteOpen(false)
        setSelectedId(null)
      },
    })
  }

  const stats = useMemo(() => {
    const active = suppliers.filter((s) => s.reference_count > 0).length
    const totalRefs = suppliers.reduce((sum, s) => sum + s.reference_count, 0)
    const leadTimes = suppliers.map((s) => s.avg_lead_time_days).filter((v): v is number => v != null)
    const avgLead = leadTimes.length > 0 ? Math.round(leadTimes.reduce((a, b) => a + b, 0) / leadTimes.length) : null
    return [
      { label: 'Suppliers', value: String(suppliers.length), icon: Truck },
      { label: 'Active', value: String(active), icon: Package },
      { label: 'References sourced', value: String(totalRefs), icon: Package },
      { label: 'Avg. lead time', value: avgLead != null ? `${avgLead}d` : '-', icon: Clock },
    ]
  }, [suppliers])

  return (
    <AppLayout
      header={
        <PageHeader title="Suppliers" subtitle="Sourcing and lead times">
          <Button size="sm" onClick={openNewDialog}>
            <Plus className="size-4" />
            Add Supplier
          </Button>
        </PageHeader>
      }
    >
      <Head title="Suppliers" />

      <div className="space-y-6">
        <FlashMessages />

        {/* Stats */}
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          {stats.map((stat) => (
            <Card key={stat.label}>
              <CardContent className="flex items-center justify-between">
                <div>
                  <div className="text-sm text-muted-foreground">{stat.label}</div>
                  <div className="mt-1 font-mono text-2xl font-bold">{stat.value}</div>
                </div>
                <stat.icon className="size-5 text-muted-foreground" />
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Supplier cards */}
        {suppliers.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
              <Truck className="size-8 text-muted-foreground" />
              <div>
                <p className="font-medium">No suppliers yet</p>
                <p className="text-sm text-muted-foreground">Add your first supplier to start tracking sourcing.</p>
              </div>
              <Button onClick={openNewDialog}>
                <Plus className="size-4" />
                Add Supplier
              </Button>
            </CardContent>
          </Card>
        ) : (
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {suppliers.map((supplier, i) => (
              <Card
                key={supplier.id}
                className="cursor-pointer gap-0 overflow-hidden py-0 transition-colors hover:border-primary"
                onClick={() => setSelectedId(supplier.id)}
              >
                <div className="flex items-center gap-3 border-b p-4">
                  <div className={`flex size-10 shrink-0 items-center justify-center rounded-lg font-mono text-sm font-bold text-white ${AVATAR_COLORS[i % AVATAR_COLORS.length]}`}>
                    {initials(supplier.name)}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-semibold">{supplier.name}</div>
                    <div className="font-mono text-xs text-muted-foreground">{supplier.country || '-'}</div>
                  </div>
                  <Badge variant={supplier.reference_count > 0 ? 'default' : 'secondary'} className="shrink-0">
                    {supplier.reference_count > 0 ? 'Active' : 'No components'}
                  </Badge>
                </div>
                <div className="grid grid-cols-2 gap-3 p-4 text-sm">
                  <div>
                    <div className="text-xs text-muted-foreground">References</div>
                    <div className="font-mono font-semibold">{supplier.reference_count}</div>
                  </div>
                  <div>
                    <div className="text-xs text-muted-foreground">Stock value</div>
                    <div className="font-mono font-semibold">{formatMoney(supplier.stock_value)}</div>
                  </div>
                  <div>
                    <div className="text-xs text-muted-foreground">Lead time</div>
                    <div className="font-mono font-semibold">{supplier.avg_lead_time_days != null ? `${supplier.avg_lead_time_days}d` : '-'}</div>
                  </div>
                  <div>
                    <div className="text-xs text-muted-foreground">Last order</div>
                    <div className="font-mono font-semibold">{supplier.last_order_at ? formatDate(supplier.last_order_at) : '-'}</div>
                  </div>
                </div>
                <div className="flex items-center justify-between gap-2 border-t p-3">
                  <span className="min-w-0 truncate font-mono text-xs text-muted-foreground">{supplier.email || '-'}</span>
                  {supplier.email && (
                    <Button
                      variant="outline"
                      size="sm"
                      className="h-7 shrink-0 text-xs"
                      asChild
                      onClick={(e) => e.stopPropagation()}
                    >
                      <a href={`mailto:${supplier.email}`}>
                        <Mail className="size-3.5" />
                        Contact
                      </a>
                    </Button>
                  )}
                </div>
              </Card>
            ))}
          </div>
        )}
      </div>

      {/* New supplier dialog */}
      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add supplier</DialogTitle>
          </DialogHeader>
          <form onSubmit={submitNew} className="flex flex-col gap-4">
            <Field>
              <FieldLabel>
                <Label>Name</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  placeholder="e.g. Mouser Electronics"
                  value={newForm.data.supplier.name}
                  onChange={(e) => newForm.setData('supplier', { ...newForm.data.supplier, name: e.target.value })}
                />
              </FieldContent>
              {newForm.errors['supplier.name'] && <FieldError>{newForm.errors['supplier.name']}</FieldError>}
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field>
                <FieldLabel>
                  <Label>Email</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    type="email"
                    placeholder="orders@supplier.com"
                    value={newForm.data.supplier.email}
                    onChange={(e) => newForm.setData('supplier', { ...newForm.data.supplier, email: e.target.value })}
                  />
                </FieldContent>
                {newForm.errors['supplier.email'] && <FieldError>{newForm.errors['supplier.email']}</FieldError>}
              </Field>
              <Field>
                <FieldLabel>
                  <Label>Phone</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    value={newForm.data.supplier.phone}
                    onChange={(e) => newForm.setData('supplier', { ...newForm.data.supplier, phone: e.target.value })}
                  />
                </FieldContent>
              </Field>
            </div>
            <Field>
              <FieldLabel>
                <Label>Website</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  placeholder="https://"
                  value={newForm.data.supplier.website}
                  onChange={(e) => newForm.setData('supplier', { ...newForm.data.supplier, website: e.target.value })}
                />
              </FieldContent>
              {newForm.errors['supplier.website'] && <FieldError>{newForm.errors['supplier.website']}</FieldError>}
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field>
                <FieldLabel>
                  <Label>City</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    value={newForm.data.supplier.city}
                    onChange={(e) => newForm.setData('supplier', { ...newForm.data.supplier, city: e.target.value })}
                  />
                </FieldContent>
              </Field>
              <Field>
                <FieldLabel>
                  <Label>Country</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    value={newForm.data.supplier.country}
                    onChange={(e) => newForm.setData('supplier', { ...newForm.data.supplier, country: e.target.value })}
                  />
                </FieldContent>
              </Field>
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setNewOpen(false)}>Cancel</Button>
              <Button type="submit" disabled={newForm.processing}>Add supplier</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Edit supplier dialog */}
      <Dialog open={editOpen} onOpenChange={setEditOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit supplier</DialogTitle>
          </DialogHeader>
          <form onSubmit={submitEdit} className="flex flex-col gap-4">
            <Field>
              <FieldLabel>
                <Label>Name</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  value={editForm.data.supplier.name}
                  onChange={(e) => editForm.setData('supplier', { ...editForm.data.supplier, name: e.target.value })}
                />
              </FieldContent>
              {editForm.errors['supplier.name'] && <FieldError>{editForm.errors['supplier.name']}</FieldError>}
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field>
                <FieldLabel>
                  <Label>Email</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    type="email"
                    value={editForm.data.supplier.email}
                    onChange={(e) => editForm.setData('supplier', { ...editForm.data.supplier, email: e.target.value })}
                  />
                </FieldContent>
                {editForm.errors['supplier.email'] && <FieldError>{editForm.errors['supplier.email']}</FieldError>}
              </Field>
              <Field>
                <FieldLabel>
                  <Label>Phone</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    value={editForm.data.supplier.phone}
                    onChange={(e) => editForm.setData('supplier', { ...editForm.data.supplier, phone: e.target.value })}
                  />
                </FieldContent>
              </Field>
            </div>
            <Field>
              <FieldLabel>
                <Label>Website</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  value={editForm.data.supplier.website}
                  onChange={(e) => editForm.setData('supplier', { ...editForm.data.supplier, website: e.target.value })}
                />
              </FieldContent>
              {editForm.errors['supplier.website'] && <FieldError>{editForm.errors['supplier.website']}</FieldError>}
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field>
                <FieldLabel>
                  <Label>City</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    value={editForm.data.supplier.city}
                    onChange={(e) => editForm.setData('supplier', { ...editForm.data.supplier, city: e.target.value })}
                  />
                </FieldContent>
              </Field>
              <Field>
                <FieldLabel>
                  <Label>Country</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    value={editForm.data.supplier.country}
                    onChange={(e) => editForm.setData('supplier', { ...editForm.data.supplier, country: e.target.value })}
                  />
                </FieldContent>
              </Field>
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setEditOpen(false)}>Cancel</Button>
              <Button type="submit" disabled={editForm.processing}>Save</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation */}
      <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete this supplier?</AlertDialogTitle>
            <AlertDialogDescription>
              <span className="font-semibold text-foreground">{selected?.name}</span> will be removed along with its linked component pricing.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={confirmDelete} className="bg-destructive text-white hover:bg-destructive/90">
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Supplier detail sheet */}
      <Sheet open={!!selected} onOpenChange={(open) => !open && setSelectedId(null)}>
        <SheetContent className="w-full gap-0 overflow-y-auto sm:max-w-lg">
          {selected && (
            <>
              <SheetHeader className="border-b">
                <div className="flex items-center gap-3">
                  <div className={`flex size-11 shrink-0 items-center justify-center rounded-lg font-mono text-sm font-bold text-white ${AVATAR_COLORS[suppliers.indexOf(selected) % AVATAR_COLORS.length]}`}>
                    {initials(selected.name)}
                  </div>
                  <div className="min-w-0 flex-1">
                    <SheetTitle>{selected.name}</SheetTitle>
                    <div className="font-mono text-xs text-muted-foreground">
                      {selected.country || '-'}{selected.email ? ` · ${selected.email}` : ''}
                    </div>
                  </div>
                  <Badge variant={selected.reference_count > 0 ? 'default' : 'secondary'} className="shrink-0">
                    {selected.reference_count > 0 ? 'Active' : 'No components'}
                  </Badge>
                </div>
              </SheetHeader>

              <div className="flex flex-1 flex-col gap-5 overflow-y-auto p-4">
                <div className="grid grid-cols-3 gap-2">
                  <div className="rounded-lg bg-muted p-3">
                    <div className="text-xs text-muted-foreground">Lead time</div>
                    <div className="font-mono text-lg font-bold">{selected.avg_lead_time_days != null ? `${selected.avg_lead_time_days}d` : '-'}</div>
                  </div>
                  <div className="rounded-lg bg-muted p-3">
                    <div className="text-xs text-muted-foreground">Orders</div>
                    <div className="font-mono text-lg font-bold">{selected.order_count}</div>
                  </div>
                  <div className="rounded-lg bg-muted p-3">
                    <div className="text-xs text-muted-foreground">Stock value</div>
                    <div className="font-mono text-lg font-bold">{formatMoney(selected.stock_value)}</div>
                  </div>
                </div>

                <div>
                  <h3 className="mb-2 text-sm font-semibold">Orders placed</h3>
                  {selected.orders.length > 0 ? (
                    <div className="divide-y rounded-lg border">
                      {selected.orders.map((order) => (
                        <div key={order.id} className="flex items-center gap-3 px-3 py-2.5 text-sm">
                          <span className="shrink-0 font-mono font-semibold">{order.reference || `#${order.id}`}</span>
                          <span className="min-w-0 flex-1 truncate font-mono text-xs text-muted-foreground">
                            {order.ordered_at ? formatDate(order.ordered_at) : '-'}
                          </span>
                          <Badge className={PURCHASE_STATUS_META[order.status].className} variant="outline">
                            {PURCHASE_STATUS_META[order.status].label}
                          </Badge>
                          <span className="w-16 shrink-0 text-right font-mono font-semibold">{formatMoney(order.total_amount)}</span>
                        </div>
                      ))}
                    </div>
                  ) : (
                    <div className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">
                      No purchase orders recorded yet.
                    </div>
                  )}
                </div>

                <div>
                  <h3 className="mb-2 text-sm font-semibold">
                    Components sourced <span className="font-normal text-muted-foreground">· {selected.reference_count}</span>
                  </h3>
                  {selected.components.length > 0 ? (
                    <div className="divide-y rounded-lg border">
                      {selected.components.map((component) => (
                        <div key={component.id} className="flex items-center gap-3 px-3 py-2.5 text-sm">
                          <span className={`size-1.5 shrink-0 rounded-sm ${component.low_stock ? 'bg-amber-500' : 'bg-muted-foreground'}`} />
                          <div className="min-w-0 flex-1">
                            <div className="truncate font-mono font-semibold">{component.reference}</div>
                            <div className="truncate text-xs text-muted-foreground">{component.name}</div>
                          </div>
                          {component.unit_price != null && (
                            <span className="shrink-0 font-mono text-xs text-muted-foreground">{component.unit_price.toFixed(2)} €</span>
                          )}
                          <span className="w-14 shrink-0 text-right font-mono font-semibold">{component.quantity}</span>
                        </div>
                      ))}
                    </div>
                  ) : (
                    <div className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">
                      No components sourced from this supplier yet.
                    </div>
                  )}
                </div>
              </div>

              <SheetFooter className="flex-row border-t">
                <Button variant="outline" className="flex-1" onClick={openEditDialog}>
                  <Pencil className="size-4" />
                  Edit
                </Button>
                <Button variant="outline" className="text-destructive" onClick={() => setDeleteOpen(true)}>
                  <Trash2 className="size-4" />
                </Button>
              </SheetFooter>
            </>
          )}
        </SheetContent>
      </Sheet>
    </AppLayout>
  )
}
