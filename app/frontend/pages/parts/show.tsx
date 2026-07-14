import { Head, Link, router, useForm } from '@inertiajs/react'
import { FormEvent, useState } from 'react'
import {
  ArrowLeft, ArrowDown, ArrowUp, ArrowLeftRight, Cpu, MapPin,
  Pencil, Trash2, ExternalLink,
} from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { SidebarTrigger } from '@/components/ui/sidebar'
import { usePermissions } from '@/hooks/use-permissions'
import { ReadOnlyBadge } from '@/components/read-only-badge'
import { FlashMessages } from '@/components/flash-messages'
import { EditPartDialog } from '@/components/edit-part-dialog'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
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
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

interface PartSupplierEntry {
  id: number
  supplier_id: number
  supplier_name: string
  supplier_sku: string | null
  unit_price: number | null
  lead_time_days: number | null
  url: string | null
  is_preferred: boolean
}

interface PartDetail {
  id: number
  name: string
  mpn: string | null
  sku: string | null
  barcode: string | null
  manufacturer: string | null
  description: string | null
  value: string | null
  tolerance: string | null
  voltage_rating: string | null
  power_rating: string | null
  package_type: string | null
  status: 'active' | 'discontinued' | 'obsolete'
  total_quantity: number
  min_stock_threshold: number
  target_stock: number | null
  unit_price: number | null
  rohs_compliant: boolean
  storage_notes: string | null
  category: { id: number; name: string; color: string | null } | null
  footprint: { id: number; name: string } | null
  tags: { id: number; name: string; color: string | null }[]
  part_suppliers: PartSupplierEntry[]
}

interface StorageEntry {
  location_id: number
  location_name: string
  location_path: string[]
  quantity: number
}

interface MovementEntry {
  id: number
  created_at: string
  movement_type: 'in' | 'out' | 'adjustment'
  quantity_delta: number
  reason: string | null
  location_name: string
  user_name: string | null
}

interface LocationOption {
  id: number
  name: string
}

interface PartShowProps {
  part: PartDetail
  storages: StorageEntry[]
  movements: MovementEntry[]
  storage_locations: LocationOption[]
  categories: { id: number; name: string }[]
  footprints: { id: number; name: string; mounting_type: string | null }[]
  suppliers: { id: number; name: string }[]
  tags: { id: number; name: string; color: string | null }[]
  supplier_lookup_enabled: boolean
  ipn_manual_entry: boolean
}

const STOCK_STATUS_META = {
  out: { label: 'Out of stock', className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400', bar: 'bg-red-500' },
  low: { label: 'Low stock', className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400', bar: 'bg-amber-500' },
  ok: { label: 'In stock', className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400', bar: 'bg-emerald-500' },
}

const MOVEMENT_META: Record<MovementEntry['movement_type'], { label: string; className: string; sign: string }> = {
  in: { label: 'In', className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400', sign: 'text-emerald-600 dark:text-emerald-400' },
  out: { label: 'Out', className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400', sign: 'text-red-600 dark:text-red-400' },
  adjustment: { label: 'Adjustment', className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400', sign: '' },
}

function partRef(part: PartDetail): string {
  return part.mpn || part.sku || part.name
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, { day: '2-digit', month: '2-digit', year: 'numeric' })
}

interface MovementFormData {
  stock_movement: {
    part_id: number
    storage_location_id: string
    movement_type: 'in' | 'out'
    quantity: string
    reason: string
  }
}

export default function PartShow({ part, storages, movements, storage_locations, categories, footprints, suppliers, tags, supplier_lookup_enabled, ipn_manual_entry }: PartShowProps) {
  const { canWrite } = usePermissions()
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [mvtOpen, setMvtOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)

  const stockKey = part.total_quantity === 0 ? 'out' : part.total_quantity < part.min_stock_threshold ? 'low' : 'ok'
  const stockMeta = STOCK_STATUS_META[stockKey]

  const gaugeMax = Math.max(part.target_stock ?? 0, part.min_stock_threshold * 2, part.total_quantity, 1)
  const fillPct = Math.min(100, (part.total_quantity / gaugeMax) * 100)
  const thresholdPct = Math.min(100, (part.min_stock_threshold / gaugeMax) * 100)

  const preferred = part.part_suppliers.find((ps) => ps.is_preferred) ?? part.part_suppliers[0]

  const specs: [string, string][] = []
  if (part.manufacturer) specs.push(['Manufacturer', part.manufacturer])
  if (part.value) specs.push(['Value', part.value])
  if (part.tolerance) specs.push(['Tolerance', part.tolerance])
  if (part.voltage_rating) specs.push(['Voltage rating', part.voltage_rating])
  if (part.power_rating) specs.push(['Power rating', part.power_rating])
  if (part.package_type) specs.push(['Package', part.package_type])
  if (part.footprint) specs.push(['Footprint', part.footprint.name])
  if (part.barcode) specs.push(['Barcode', part.barcode])
  specs.push(['RoHS', part.rohs_compliant ? 'Compliant' : 'Not verified'])

  const mvtForm = useForm<MovementFormData>({
    stock_movement: {
      part_id: part.id,
      storage_location_id: storages[0]?.location_id.toString() ?? '',
      movement_type: 'in',
      quantity: '',
      reason: '',
    },
  })

  const openMovement = (type: 'in' | 'out') => {
    mvtForm.reset()
    mvtForm.clearErrors()
    mvtForm.setData('stock_movement', {
      ...mvtForm.data.stock_movement,
      movement_type: type,
      quantity: '',
      reason: '',
    })
    setMvtOpen(true)
  }

  const submitMovement = (e: FormEvent) => {
    e.preventDefault()
    mvtForm.post('/stock_movements', {
      preserveScroll: true,
      onSuccess: () => setMvtOpen(false),
    })
  }

  const confirmDelete = () => {
    router.delete(`/parts/${part.id}`)
  }

  const mvtType = mvtForm.data.stock_movement.movement_type

  return (
    <AppLayout
      header={
        <header className="flex shrink-0 flex-wrap items-center gap-3 border-b bg-background px-4 py-3 sm:px-5">
          <SidebarTrigger className="-ml-1 md:hidden" />
          <Button variant="outline" size="icon-sm" asChild>
            <Link href="/parts" aria-label="Back to inventory">
              <ArrowLeft className="size-4" />
            </Link>
          </Button>
          <div className="flex items-center gap-1.5 text-sm text-muted-foreground">
            <Link href="/parts" className="hover:text-foreground">Inventory</Link>
            {part.category && (
              <>
                <span className="opacity-50">/</span>
                <span className="font-medium text-foreground">{part.category.name}</span>
              </>
            )}
            <span className="opacity-50">/</span>
            <span className="font-mono font-medium text-foreground">{partRef(part)}</span>
          </div>
          <div className="flex-1" />
          <ReadOnlyBadge />
          {canWrite && (
            <Button variant="outline" size="icon-sm" className="text-destructive" onClick={() => setDeleteOpen(true)} aria-label="Delete part">
              <Trash2 className="size-4" />
            </Button>
          )}
          {canWrite && (
            <Button variant="outline" size="sm" onClick={() => setEditOpen(true)}>
              <Pencil className="size-4" />
              Edit
            </Button>
          )}
          {canWrite && (
            <Button size="sm" onClick={() => openMovement('in')}>
              <ArrowLeftRight className="size-4" />
              Stock in / out
            </Button>
          )}
        </header>
      }
    >
      <Head title={partRef(part)} />

      <div className="mx-auto max-w-5xl space-y-4">
        <FlashMessages />

        {/* Header card */}
        <Card className="py-5">
          <CardContent className="flex flex-wrap items-start gap-4">
            <div
              className="flex size-13 shrink-0 items-center justify-center rounded-xl bg-muted"
              style={part.category?.color ? { backgroundColor: `${part.category.color}22`, color: part.category.color } : undefined}
            >
              <Cpu className="size-6" />
            </div>
            <div className="min-w-[220px] flex-1">
              <div className="flex flex-wrap items-center gap-2.5">
                <h1 className="font-mono text-xl font-bold tracking-tight">{partRef(part)}</h1>
                <span className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${stockMeta.className}`}>
                  {stockMeta.label}
                </span>
                {part.status !== 'active' && (
                  <Badge variant="outline" className="capitalize">{part.status}</Badge>
                )}
              </div>
              <div className="mt-1 text-sm">{part.name}</div>
              <div className="mt-2 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                {part.category && (
                  <span className="inline-flex items-center gap-1.5">
                    <span
                      className="size-2 rounded-sm"
                      style={{ backgroundColor: part.category.color || 'var(--muted-foreground)' }}
                    />
                    {part.category.name}
                  </span>
                )}
                {part.value && (
                  <>
                    <span className="opacity-50">·</span>
                    <span className="font-mono">{part.value}</span>
                  </>
                )}
                {part.package_type && (
                  <>
                    <span className="opacity-50">·</span>
                    <span className="rounded-md bg-muted px-1.5 py-0.5 font-mono">{part.package_type}</span>
                  </>
                )}
              </div>
              {part.description && (
                <p className="mt-2 max-w-xl text-sm text-muted-foreground">{part.description}</p>
              )}
              {part.tags.length > 0 && (
                <div className="mt-2 flex flex-wrap items-center gap-1.5">
                  {part.tags.map((tag) => (
                    <Badge
                      key={tag.id}
                      variant="outline"
                      className="gap-1.5"
                      style={tag.color ? { borderColor: tag.color } : undefined}
                    >
                      <span
                        className="size-2 rounded-full border"
                        style={{ backgroundColor: tag.color || 'var(--muted)' }}
                      />
                      {tag.name}
                    </Badge>
                  ))}
                </div>
              )}
            </div>
          </CardContent>
        </Card>

        {/* Stat row */}
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          {[
            { label: 'In stock', value: part.total_quantity.toLocaleString(), className: stockKey === 'ok' ? '' : stockKey === 'low' ? 'text-amber-600 dark:text-amber-400' : 'text-destructive' },
            { label: 'Min. threshold', value: part.min_stock_threshold.toLocaleString(), className: '' },
            { label: 'Unit price', value: part.unit_price != null ? part.unit_price.toFixed(2) : '—', className: '' },
            { label: 'Stock value', value: part.unit_price != null ? (part.unit_price * part.total_quantity).toFixed(2) : '—', className: '' },
          ].map((stat) => (
            <Card key={stat.label} className="py-4">
              <CardContent className="px-4">
                <div className="text-xs text-muted-foreground">{stat.label}</div>
                <div className={`mt-1 font-mono text-xl font-bold ${stat.className}`}>{stat.value}</div>
              </CardContent>
            </Card>
          ))}
        </div>

        <div className="grid items-start gap-4 lg:grid-cols-[1.5fr_1fr]">
          {/* Left column */}
          <div className="space-y-4">
            {/* Stock level */}
            <Card className="py-5">
              <CardContent>
                <div className="mb-3 flex items-center justify-between">
                  <h2 className="text-sm font-semibold">Stock level</h2>
                  <span className="font-mono text-xs text-muted-foreground">
                    {part.total_quantity.toLocaleString()} / {gaugeMax.toLocaleString()}
                  </span>
                </div>
                <div className="h-2.5 overflow-hidden rounded-full bg-muted">
                  <div className={`h-full rounded-full ${stockMeta.bar}`} style={{ width: `${fillPct}%` }} />
                </div>
                <div className="relative mt-1 h-5">
                  <div
                    className="absolute -translate-x-1/2 text-[10.5px] whitespace-nowrap text-muted-foreground"
                    style={{ left: `${thresholdPct}%` }}
                  >
                    ▲ threshold {part.min_stock_threshold}
                  </div>
                </div>
                {canWrite && (
                  <div className="mt-2 flex gap-2.5">
                    <Button variant="outline" className="flex-1 text-emerald-600 dark:text-emerald-400" onClick={() => openMovement('in')}>
                      <ArrowDown className="size-4" />
                      Stock in
                    </Button>
                    <Button variant="outline" className="flex-1 text-red-600 dark:text-red-400" onClick={() => openMovement('out')}>
                      <ArrowUp className="size-4" />
                      Stock out
                    </Button>
                  </div>
                )}
              </CardContent>
            </Card>

            {/* Movement history */}
            <Card className="gap-0 py-0">
              <CardHeader className="flex flex-row items-center justify-between border-b py-4">
                <CardTitle className="text-sm">Movement history</CardTitle>
                <Link href="/stock_movements" className="text-xs font-medium text-muted-foreground hover:text-foreground">
                  See all →
                </Link>
              </CardHeader>
              <CardContent className="p-0">
                {movements.length > 0 ? (
                  <div className="divide-y">
                    {movements.map((movement) => {
                      const meta = MOVEMENT_META[movement.movement_type]
                      return (
                        <div key={movement.id} className="flex items-center gap-3 px-4 py-2.5 text-sm">
                          <span className="shrink-0 font-mono text-xs text-muted-foreground">{formatDate(movement.created_at)}</span>
                          <Badge className={meta.className} variant="outline">{meta.label}</Badge>
                          <span className="min-w-0 flex-1 truncate text-xs text-muted-foreground">
                            {movement.location_name}
                            {movement.reason ? ` · ${movement.reason}` : ''}
                          </span>
                          <span className={`shrink-0 font-mono font-semibold ${meta.sign}`}>
                            {movement.quantity_delta > 0 ? `+${movement.quantity_delta}` : movement.quantity_delta}
                          </span>
                        </div>
                      )
                    })}
                  </div>
                ) : (
                  <p className="p-5 text-sm text-muted-foreground">No movements recorded for this part yet.</p>
                )}
              </CardContent>
            </Card>
          </div>

          {/* Right column */}
          <div className="space-y-4">
            {/* Location */}
            <Card className="py-5">
              <CardContent>
                <h2 className="mb-3 text-sm font-semibold">Location</h2>
                {storages.length > 0 ? (
                  <div className="space-y-2.5">
                    {storages.map((storage) => (
                      <div key={storage.location_id} className="flex items-center justify-between gap-2 text-sm">
                        <span className="flex min-w-0 flex-wrap items-center gap-1 text-xs">
                          {storage.location_path.map((segment, i) => (
                            <span key={i} className="flex items-center gap-1">
                              {i > 0 && <span className="text-muted-foreground">/</span>}
                              <span className={i === storage.location_path.length - 1 ? 'rounded-md bg-muted px-1.5 py-0.5 font-mono font-semibold' : 'text-muted-foreground'}>
                                {segment}
                              </span>
                            </span>
                          ))}
                        </span>
                        <span className="shrink-0 font-mono text-sm font-semibold">{storage.quantity}</span>
                      </div>
                    ))}
                  </div>
                ) : (
                  <p className="text-sm text-muted-foreground">Not stored anywhere yet.</p>
                )}
                <Button variant="outline" size="sm" className="mt-3 w-full" asChild>
                  <Link href="/storage_locations">
                    <MapPin className="size-3.5" />
                    View in zones
                  </Link>
                </Button>
              </CardContent>
            </Card>

            {/* Specs */}
            <Card className="gap-0 py-0">
              <CardHeader className="border-b py-4">
                <CardTitle className="text-sm">Specifications</CardTitle>
              </CardHeader>
              <CardContent className="p-0">
                <div className="divide-y">
                  {specs.map(([key, value]) => (
                    <div key={key} className="flex items-center justify-between gap-3 px-4 py-2 text-sm">
                      <span className="text-muted-foreground">{key}</span>
                      <span className="text-right font-mono font-medium">{value}</span>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>

            {/* Supplier */}
            <Card className="py-5">
              <CardContent>
                <h2 className="mb-3 text-sm font-semibold">Sourcing</h2>
                {preferred ? (
                  <div className="flex items-center gap-3">
                    <div className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-blue-600 font-mono text-xs font-bold text-white">
                      {preferred.supplier_name.slice(0, 2).toUpperCase()}
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-sm font-semibold">{preferred.supplier_name}</div>
                      <div className="text-xs text-muted-foreground">
                        {preferred.unit_price != null ? `Unit ${preferred.unit_price.toFixed(2)}` : 'No price'}
                        {preferred.lead_time_days != null ? ` · lead ${preferred.lead_time_days}d` : ''}
                      </div>
                    </div>
                    <Button variant="outline" size="icon-sm" asChild>
                      <Link href="/suppliers" aria-label="View suppliers">
                        <ExternalLink className="size-4" />
                      </Link>
                    </Button>
                  </div>
                ) : (
                  <p className="text-sm text-muted-foreground">No supplier linked to this part.</p>
                )}
              </CardContent>
            </Card>
          </div>
        </div>
      </div>

      {/* Stock movement modal */}
      <Dialog open={mvtOpen} onOpenChange={setMvtOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Record a movement</DialogTitle>
          </DialogHeader>
          <form onSubmit={submitMovement} className="flex flex-col gap-4">
            <div className="grid grid-cols-2 gap-2">
              {(['in', 'out'] as const).map((type) => (
                <button
                  key={type}
                  type="button"
                  onClick={() => mvtForm.setData('stock_movement', { ...mvtForm.data.stock_movement, movement_type: type })}
                  className={`flex items-center justify-center gap-2 rounded-lg border-[1.5px] p-2.5 text-sm font-semibold transition-colors ${
                    mvtType === type ? 'border-primary bg-accent' : 'border-border hover:bg-accent'
                  }`}
                >
                  {type === 'in' ? <ArrowDown className="size-4 text-emerald-600 dark:text-emerald-400" /> : <ArrowUp className="size-4 text-red-600 dark:text-red-400" />}
                  {type === 'in' ? 'Stock in' : 'Stock out'}
                </button>
              ))}
            </div>
            <Field>
              <FieldLabel><Label>Location</Label></FieldLabel>
              <FieldContent>
                <Select
                  value={mvtForm.data.stock_movement.storage_location_id}
                  onValueChange={(value) => mvtForm.setData('stock_movement', { ...mvtForm.data.stock_movement, storage_location_id: value })}
                >
                  <SelectTrigger className="w-full"><SelectValue placeholder="Select a location" /></SelectTrigger>
                  <SelectContent>
                    {storage_locations.map((location) => (
                      <SelectItem key={location.id} value={location.id.toString()}>{location.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FieldContent>
              {mvtForm.errors['stock_movement.storage_location_id'] && (
                <FieldError>{mvtForm.errors['stock_movement.storage_location_id']}</FieldError>
              )}
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field>
                <FieldLabel><Label>Quantity</Label></FieldLabel>
                <FieldContent>
                  <Input
                    inputMode="numeric"
                    placeholder="0"
                    value={mvtForm.data.stock_movement.quantity}
                    onChange={(e) => mvtForm.setData('stock_movement', { ...mvtForm.data.stock_movement, quantity: e.target.value.replace(/[^0-9]/g, '') })}
                  />
                </FieldContent>
                {(mvtForm.errors as Record<string, string>)['stock_movement.quantity_delta'] && (
                  <FieldError>{(mvtForm.errors as Record<string, string>)['stock_movement.quantity_delta']}</FieldError>
                )}
              </Field>
              <Field>
                <FieldLabel><Label>Reason</Label></FieldLabel>
                <FieldContent>
                  <Input
                    placeholder="e.g. Project X"
                    value={mvtForm.data.stock_movement.reason}
                    onChange={(e) => mvtForm.setData('stock_movement', { ...mvtForm.data.stock_movement, reason: e.target.value })}
                  />
                </FieldContent>
              </Field>
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setMvtOpen(false)}>Cancel</Button>
              <Button
                type="submit"
                disabled={mvtForm.processing || !mvtForm.data.stock_movement.quantity || !mvtForm.data.stock_movement.storage_location_id}
              >
                Record movement
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation */}
      <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete this part?</AlertDialogTitle>
            <AlertDialogDescription>
              <span className="font-mono font-semibold text-foreground">{partRef(part)}</span> will be removed along with its stock records. Parts with recorded movements cannot be deleted.
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

      {/* Edit Part modal */}
      <EditPartDialog
        partId={editOpen ? part.id : null}
        open={editOpen}
        onOpenChange={setEditOpen}
        categories={categories}
        footprints={footprints}
        suppliers={suppliers}
        tags={tags}
        supplierLookupEnabled={supplier_lookup_enabled}
        ipnManualEntry={ipn_manual_entry}
      />
    </AppLayout>
  )
}
