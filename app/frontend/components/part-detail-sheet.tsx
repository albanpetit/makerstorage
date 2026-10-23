import { Link, router, useForm } from '@inertiajs/react'
import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react'
import {
  ArrowDown, ArrowUp, ArrowLeftRight, Cpu, MapPin,
  Pencil, Printer, Trash2, ExternalLink, Loader2, CircleAlert, HandHelping,
} from 'lucide-react'

import { usePermissions } from '@/hooks/use-permissions'
import { EditPartDialog } from '@/components/edit-part-dialog'
import { PrintLabelsDialog } from '@/components/print-labels-dialog'
import { labelForPart } from '@/lib/labels'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetFooter,
} from '@/components/ui/sheet'
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
import { StorageLocationSelect, type StorageLocationOption } from '@/components/storage-location-select'
import { LIFECYCLE_META } from '@/components/parts/part-meta'
import { PartFiles, type PartFile } from '@/components/parts/part-files'
import { formatUnitPrice, type PriceBreak } from '@/lib/money'
import { PriceHistory, type PricePoint } from '@/components/parts/price-history'
import { t, intlLocale, tn, tx } from '@/lib/i18n'

interface PartSupplierEntry {
  id: number
  supplier_id: number
  supplier_name: string
  supplier_sku: string | null
  unit_price: number | null
  lead_time_days: number | null
  url: string | null
  is_preferred: boolean
  price_breaks: PriceBreak[]
}

interface PartDetail {
  id: number
  name: string
  ipn: string | null
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
  parameters: { id: number; name: string; value: string; display: string }[]
  location_names: string[]
  files: PartFile[]
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

interface ReservationEntry {
  project_id: number
  reference: string | null
  name: string
  quantity: number
}

interface LoanEntry {
  loan_id: number
  reference: string | null
  borrower_name: string
  quantity: number
  due_on: string | null
  overdue: boolean
}

// Usage read from the ledger (PartConsumption) and the threshold it suggests.
interface ConsumptionEntry {
  window_days: number
  consumed: number
  movements: number
  monthly_rate: number
  days_left: number | null
  cover_days: number | null
  suggested_threshold: number | null
  last_used_at: string | null
  months: { month: string; quantity: number }[]
}

interface Category {
  id: number
  name: string
}

interface Footprint {
  id: number
  name: string
  mounting_type: string | null
}

interface Supplier {
  id: number
  name: string
}

interface Tag {
  id: number
  name: string
  color: string | null
}

// The payload returned by GET /parts/:id (JSON). It carries both the part
// detail and the option lists the embedded edit-part modal needs, so the sheet
// is fully self-sufficient — any page can mount it with just a part id.
interface PartShowPayload {
  part: PartDetail
  storages: StorageEntry[]
  movements: MovementEntry[]
  reservations: ReservationEntry[]
  loans: LoanEntry[]
  price_history: PricePoint[]
  consumption: ConsumptionEntry
  storage_locations: StorageLocationOption[]
  categories: Category[]
  footprints: Footprint[]
  suppliers: Supplier[]
  tags: Tag[]
  supplier_lookup_enabled: boolean
  ipn_manual_entry: boolean
}

interface PartDetailSheetProps {
  partId: number | null
  open: boolean
  onOpenChange: (open: boolean) => void
}

const STOCK_STATUS_META = {
  out: { get label() { return t('Out of stock') }, className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400', bar: 'bg-red-500' },
  low: { get label() { return t('Low stock') }, className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400', bar: 'bg-amber-500' },
  ok: { get label() { return t('In stock') }, className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400', bar: 'bg-emerald-500' },
}

const MOVEMENT_META: Record<MovementEntry['movement_type'], { label: string; className: string; sign: string }> = {
  in: { get label() { return t('In') }, className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400', sign: 'text-emerald-600 dark:text-emerald-400' },
  out: { get label() { return t('Out') }, className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400', sign: 'text-red-600 dark:text-red-400' },
  adjustment: { get label() { return t('Adjustment') }, className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400', sign: '' },
}

function partRef(part: PartDetail): string {
  return part.mpn || part.sku || part.name
}

// A calendar day ("2026-10-20"), read as local midnight so it doesn't shift.
function formatDay(day: string) {
  return new Date(`${day}T00:00:00`).toLocaleDateString(undefined, { day: '2-digit', month: '2-digit' })
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(intlLocale(), { day: '2-digit', month: '2-digit', year: 'numeric' })
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

export function PartDetailSheet({
  partId,
  open,
  onOpenChange,
}: PartDetailSheetProps) {
  const { canWrite } = usePermissions()
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState('')
  const [payload, setPayload] = useState<PartShowPayload | null>(null)

  const [deleteOpen, setDeleteOpen] = useState(false)
  const [labelOpen, setLabelOpen] = useState(false)
  const [mvtOpen, setMvtOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)

  // Fetch the full part detail from the JSON endpoint. Reused after a stock
  // movement or edit so the sidebar reflects the change without a full reload.
  const load = useCallback(() => {
    if (partId == null) return
    let cancelled = false
    setLoading(true)
    setLoadError('')
    fetch(`/parts/${partId}`, { headers: { Accept: 'application/json' } })
      .then((res) => {
        if (!res.ok) throw new Error('Failed to load part')
        return res.json()
      })
      .then((body: PartShowPayload) => {
        if (cancelled) return
        setPayload(body)
        setLoading(false)
      })
      .catch(() => {
        if (cancelled) return
        setLoadError(t('Could not load this part. Please try again.'))
        setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [partId])

  useEffect(() => {
    if (!open || partId == null) return
    setPayload(null)
    const cleanup = load()
    return cleanup
  }, [open, partId, load])

  const mvtForm = useForm<MovementFormData>({
    stock_movement: {
      part_id: partId ?? 0,
      storage_location_id: '',
      movement_type: 'in',
      quantity: '',
      reason: '',
    },
  })

  // Zones already holding this part show their quantity in the picker.
  const movementLocations = useMemo(() => {
    const stored = new Map((payload?.storages ?? []).map((s) => [s.location_id, s.quantity]))
    return (payload?.storage_locations ?? []).map((location) =>
      stored.has(location.id) ? { ...location, hint: t('{quantity} in stock', { quantity: stored.get(location.id)! }) } : location
    )
  }, [payload])

  const openMovement = (type: 'in' | 'out') => {
    if (!payload) return
    mvtForm.clearErrors()
    mvtForm.setData('stock_movement', {
      part_id: payload.part.id,
      storage_location_id: payload.storages[0]?.location_id.toString() ?? '',
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
      preserveState: true,
      onSuccess: () => {
        setMvtOpen(false)
        load()
      },
    })
  }

  const applySuggestedThreshold = () => {
    if (!payload) return
    router.post('/alerts/thresholds', { part_ids: [payload.part.id] }, {
      preserveScroll: true,
      preserveState: true,
      onSuccess: () => load(),
    })
  }

  const confirmDelete = () => {
    if (partId == null) return
    router.delete(`/parts/${partId}`, {
      onSuccess: () => {
        setDeleteOpen(false)
        onOpenChange(false)
      },
    })
  }

  const mvtType = mvtForm.data.stock_movement.movement_type
  const part = payload?.part

  const stockKey = part
    ? part.total_quantity === 0 ? 'out' : part.total_quantity < part.min_stock_threshold ? 'low' : 'ok'
    : 'ok'
  const stockMeta = STOCK_STATUS_META[stockKey]

  const reservedTotal = payload?.reservations.reduce((sum, r) => sum + r.quantity, 0) ?? 0
  const gaugeMax = part ? Math.max(part.target_stock ?? 0, part.min_stock_threshold * 2, part.total_quantity, 1) : 1
  const fillPct = part ? Math.min(100, (part.total_quantity / gaugeMax) * 100) : 0
  const thresholdPct = part ? Math.min(100, (part.min_stock_threshold / gaugeMax) * 100) : 0

  const preferred = part?.part_suppliers.find((ps) => ps.is_preferred) ?? part?.part_suppliers[0]

  const specs: [string, string][] = []
  if (part) {
    if (part.manufacturer) specs.push([t('Manufacturer'), part.manufacturer])
    if (part.value) specs.push([t('Value'), part.value])
    // Parameters, then the older fields a parameter doesn't already show.
    part.parameters.forEach((parameter) => specs.push([parameter.name, parameter.display]))
    const named = new Set(part.parameters.map((parameter) => parameter.name.toLowerCase()))
    if (part.tolerance && !named.has('tolerance')) specs.push([t('Tolerance'), part.tolerance])
    if (part.voltage_rating && !named.has('voltage rating')) specs.push([t('Voltage rating'), part.voltage_rating])
    if (part.power_rating && !named.has('power rating')) specs.push([t('Power rating'), part.power_rating])
    if (part.package_type) specs.push([t('Package'), part.package_type])
    if (part.footprint) specs.push([t('Footprint'), part.footprint.name])
    if (part.barcode) specs.push([t('Barcode'), part.barcode])
    specs.push(['RoHS', part.rohs_compliant ? t('Compliant') : t('Not verified')])
  }

  return (
    <>
      <Sheet open={open} onOpenChange={onOpenChange}>
        <SheetContent className="w-full gap-0 overflow-y-auto p-0 sm:max-w-xl">
          {loading && !payload ? (
            <div className="flex flex-1 items-center justify-center py-16">
              <Loader2 className="size-6 animate-spin text-muted-foreground" />
            </div>
          ) : loadError ? (
            <div className="flex flex-1 flex-col items-center justify-center gap-4 px-6 py-16">
              <Alert variant="destructive">
                <CircleAlert />
                <AlertDescription>{loadError}</AlertDescription>
              </Alert>
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>{t('Close')}</Button>
            </div>
          ) : part && payload ? (
            <>
              <SheetHeader className="border-b">
                <div className="flex items-start gap-3 pr-8">
                  <div
                    className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-muted"
                    style={part.category?.color ? { backgroundColor: `${part.category.color}22`, color: part.category.color } : undefined}
                  >
                    <Cpu className="size-5" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <SheetTitle className="font-mono">{partRef(part)}</SheetTitle>
                      <span className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${stockMeta.className}`}>
                        {stockMeta.label}
                      </span>
                      {part.status !== 'active' && (
                        <Badge variant="outline">{LIFECYCLE_META[part.status].label}</Badge>
                      )}
                    </div>
                    <div className="mt-1 text-sm text-muted-foreground">{part.name}</div>
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
                </div>
              </SheetHeader>

              <div className="flex flex-1 flex-col gap-5 overflow-y-auto p-4">
                {part.description && (
                  <p className="text-sm text-muted-foreground">{part.description}</p>
                )}

                {/* Stat row */}
                <div className="grid grid-cols-2 gap-2">
                  {[
                    { label: t('In stock'), value: part.total_quantity.toLocaleString(intlLocale()), className: stockKey === 'ok' ? '' : stockKey === 'low' ? 'text-amber-600 dark:text-amber-400' : 'text-destructive' },
                    { label: t('Min. threshold'), value: part.min_stock_threshold.toLocaleString(intlLocale()), className: '' },
                    { label: t('Unit price'), value: part.unit_price != null ? formatUnitPrice(part.unit_price) : '—', className: '' },
                    { label: t('Stock value'), value: part.unit_price != null ? (part.unit_price * part.total_quantity).toFixed(2) : '—', className: '' },
                  ].map((stat) => (
                    <div key={stat.label} className="rounded-lg bg-muted p-3">
                      <div className="text-xs text-muted-foreground">{stat.label}</div>
                      <div className={`mt-1 font-mono text-lg font-bold ${stat.className}`}>{stat.value}</div>
                    </div>
                  ))}
                </div>

                {/* Stock level */}
                <div>
                  <div className="mb-3 flex items-center justify-between">
                    <h3 className="text-sm font-semibold">{t('Stock level')}</h3>
                    <span className="font-mono text-xs text-muted-foreground">
                      {part.total_quantity.toLocaleString(intlLocale())} / {gaugeMax.toLocaleString(intlLocale())}
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
                      {t('▲ threshold {threshold}', { threshold: part.min_stock_threshold })}
                    </div>
                  </div>
                  {canWrite && (
                    <div className="mt-2 flex gap-2.5">
                      <Button variant="outline" className="flex-1 text-emerald-600 dark:text-emerald-400" onClick={() => openMovement('in')}>
                        <ArrowDown className="size-4" />
                        {t('Stock in')}
                      </Button>
                      <Button variant="outline" className="flex-1 text-red-600 dark:text-red-400" onClick={() => openMovement('out')}>
                        <ArrowUp className="size-4" />
                        {t('Stock out')}
                      </Button>
                      {part.total_quantity > 0 && (
                        <Button variant="outline" className="flex-1" asChild>
                          <Link href={`/loans?part_id=${part.id}`}>
                            <HandHelping className="size-4" />
                            {t('Lend')}
                          </Link>
                        </Button>
                      )}
                    </div>
                  )}
                </div>

                {/* Consumption */}
                <ConsumptionBlock
                  consumption={payload.consumption}
                  threshold={part.min_stock_threshold}
                  canWrite={canWrite}
                  onApply={applySuggestedThreshold}
                />

                {/* Project reservations */}
                {payload.reservations.length > 0 && (
                  <div>
                    <div className="mb-2 flex items-center justify-between">
                      <h3 className="text-sm font-semibold">{t('Reserved by projects')}</h3>
                      <span className="font-mono text-xs text-muted-foreground">
                        {t('{quantity} available', { quantity: Math.max(part.total_quantity - reservedTotal, 0) })}
                      </span>
                    </div>
                    <div className="space-y-2.5 rounded-lg border p-3">
                      {payload.reservations.map((reservation) => (
                        <div key={reservation.project_id} className="flex items-center justify-between gap-2 text-sm">
                          <Link href={`/projects/${reservation.project_id}`} className="min-w-0 truncate hover:underline">
                            {reservation.reference && <span className="mr-1.5 font-mono text-xs text-muted-foreground">{reservation.reference}</span>}
                            {reservation.name}
                          </Link>
                          <span className="shrink-0 font-mono text-sm font-semibold">{reservation.quantity}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Loans */}
                {payload.loans.length > 0 && (
                  <div>
                    <div className="mb-2 flex items-center justify-between">
                      <h3 className="text-sm font-semibold">{t('On loan')}</h3>
                      <span className="font-mono text-xs text-muted-foreground">
                        {t('{count} out', { count: payload.loans.reduce((sum, l) => sum + l.quantity, 0) })}
                      </span>
                    </div>
                    <div className="space-y-2.5 rounded-lg border p-3">
                      {payload.loans.map((loan) => (
                        <div key={loan.loan_id} className="flex items-center justify-between gap-2 text-sm">
                          <Link href={`/loans/${loan.loan_id}`} className="min-w-0 truncate hover:underline">
                            {loan.reference && <span className="mr-1.5 font-mono text-xs text-muted-foreground">{loan.reference}</span>}
                            {loan.borrower_name}
                          </Link>
                          <span className="flex shrink-0 items-center gap-2">
                            {loan.due_on && (
                              <span className={`text-xs ${loan.overdue ? 'font-medium text-destructive' : 'text-muted-foreground'}`}>
                                {loan.overdue ? 'overdue' : `due ${formatDay(loan.due_on)}`}
                              </span>
                            )}
                            <span className="font-mono text-sm font-semibold">{loan.quantity}</span>
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Location */}
                <div>
                  <h3 className="mb-2 text-sm font-semibold">{t('Location')}</h3>
                  {payload.storages.length > 0 ? (
                    <div className="space-y-2.5 rounded-lg border p-3">
                      {payload.storages.map((storage) => (
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
                    <p className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">{t('Not stored anywhere yet.')}</p>
                  )}
                  <Button variant="outline" size="sm" className="mt-3 w-full" asChild>
                    <Link href="/storage_locations">
                      <MapPin className="size-3.5" />
                      {t('View in zones')}
                    </Link>
                  </Button>
                </div>

                {/* Specifications */}
                <div>
                  <h3 className="mb-2 text-sm font-semibold">{t('Specifications')}</h3>
                  <div className="divide-y rounded-lg border">
                    {specs.map(([key, value]) => (
                      <div key={key} className="flex items-center justify-between gap-3 px-4 py-2 text-sm">
                        <span className="text-muted-foreground">{key}</span>
                        <span className="text-right font-mono font-medium">{value}</span>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Sourcing */}
                <div>
                  <h3 className="mb-2 text-sm font-semibold">{t('Sourcing')}</h3>
                  {preferred ? (
                    <div className="flex items-center gap-3 rounded-lg border p-3">
                      <div className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-blue-600 font-mono text-xs font-bold text-white">
                        {preferred.supplier_name.slice(0, 2).toUpperCase()}
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-sm font-semibold">{preferred.supplier_name}</div>
                        <div className="text-xs text-muted-foreground">
                          {preferred.unit_price != null ? t('Unit {price}', { price: formatUnitPrice(preferred.unit_price) }) : t('No price')}
                          {preferred.lead_time_days != null ? t(' · lead {days}d', { days: preferred.lead_time_days }) : ''}
                        </div>
                      </div>
                      <Button variant="outline" size="icon-sm" asChild>
                        <Link href="/suppliers" aria-label={t('View suppliers')}>
                          <ExternalLink className="size-4" />
                        </Link>
                      </Button>
                    </div>
                  ) : (
                    <p className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">{t('No supplier linked to this part.')}</p>
                  )}
                  {preferred && preferred.price_breaks.length > 0 && (
                    <div className="mt-2 flex flex-wrap gap-1.5" aria-label={t('Price breaks')}>
                      {preferred.price_breaks.map((row) => (
                        <span key={row.quantity} className="rounded-md bg-muted px-2 py-1 font-mono text-xs">
                          {t('{quantity}+: {price}', { quantity: row.quantity.toLocaleString(intlLocale()), price: formatUnitPrice(row.unit_price) })}
                        </span>
                      ))}
                    </div>
                  )}
                </div>

                {/* Price history */}
                <div>
                  <h3 className="mb-2 text-sm font-semibold">{t('Price history')}</h3>
                  <PriceHistory points={payload.price_history} />
                </div>

                <PartFiles partId={part.id} files={part.files} canWrite={canWrite} onChange={load} />

                {/* Movement history */}
                <div>
                  <div className="mb-2 flex items-center justify-between">
                    <h3 className="text-sm font-semibold">{t('Movement history')}</h3>
                    <Link href="/stock_movements" className="text-xs font-medium text-muted-foreground hover:text-foreground">
                      {t('See all →')}
                    </Link>
                  </div>
                  {payload.movements.length > 0 ? (
                    <div className="divide-y rounded-lg border">
                      {payload.movements.map((movement) => {
                        const meta = MOVEMENT_META[movement.movement_type]
                        return (
                          <div key={movement.id} className="flex items-center gap-3 px-3 py-2.5 text-sm">
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
                    <p className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">{t('No movements recorded for this part yet.')}</p>
                  )}
                </div>
              </div>

              {canWrite && (
                <SheetFooter className="flex-row border-t">
                  <Button className="flex-1" onClick={() => openMovement('in')}>
                    <ArrowLeftRight className="size-4" />
                    {t('Stock in / out')}
                  </Button>
                  <Button variant="outline" onClick={() => setLabelOpen(true)} aria-label={t('Print label')}>
                    <Printer className="size-4" />
                  </Button>
                  <Button variant="outline" onClick={() => setEditOpen(true)} aria-label={t('Edit part')}>
                    <Pencil className="size-4" />
                  </Button>
                  <Button variant="outline" className="text-destructive" onClick={() => setDeleteOpen(true)} aria-label={t('Delete part')}>
                    <Trash2 className="size-4" />
                  </Button>
                </SheetFooter>
              )}
            </>
          ) : null}
        </SheetContent>
      </Sheet>

      {/* Stock movement modal */}
      <Dialog open={mvtOpen} onOpenChange={setMvtOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{t('Record a movement')}</DialogTitle>
          </DialogHeader>
          <form onSubmit={submitMovement} className="flex min-w-0 flex-col gap-4">
            <div className="grid grid-cols-2 gap-2">
              {(['in', 'out'] as const).map((type) => (
                <Button
                  key={type}
                  type="button"
                  variant="ghost"
                  onClick={() => mvtForm.setData('stock_movement', { ...mvtForm.data.stock_movement, movement_type: type })}
                  className={`h-auto gap-2 rounded-lg border-[1.5px] p-2.5 font-semibold has-[>svg]:px-2.5 ${
                    mvtType === type ? 'border-primary bg-accent dark:hover:bg-accent' : 'border-border'
                  }`}
                >
                  {type === 'in' ? <ArrowDown className="size-4 text-emerald-600 dark:text-emerald-400" /> : <ArrowUp className="size-4 text-red-600 dark:text-red-400" />}
                  {type === 'in' ? t('Stock in') : t('Stock out')}
                </Button>
              ))}
            </div>
            <Field>
              <FieldLabel><Label>{t('Location')}</Label></FieldLabel>
              <FieldContent>
                <StorageLocationSelect
                  locations={movementLocations}
                  value={mvtForm.data.stock_movement.storage_location_id}
                  onValueChange={(value) => mvtForm.setData('stock_movement', { ...mvtForm.data.stock_movement, storage_location_id: value })}
                  placeholder={t('Select a location')}
                  allowCreate
                />
              </FieldContent>
              {mvtForm.errors['stock_movement.storage_location_id'] && (
                <FieldError>{mvtForm.errors['stock_movement.storage_location_id']}</FieldError>
              )}
            </Field>
            <div className="grid grid-cols-2 gap-4 [&>*]:min-w-0">
              <Field>
                <FieldLabel><Label>{t('Quantity')}</Label></FieldLabel>
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
                <FieldLabel><Label>{t('Reason')}</Label></FieldLabel>
                <FieldContent>
                  <Input
                    placeholder={t('e.g. Project X')}
                    value={mvtForm.data.stock_movement.reason}
                    onChange={(e) => mvtForm.setData('stock_movement', { ...mvtForm.data.stock_movement, reason: e.target.value })}
                  />
                </FieldContent>
              </Field>
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setMvtOpen(false)}>{t('Cancel')}</Button>
              <Button
                type="submit"
                disabled={mvtForm.processing || !mvtForm.data.stock_movement.quantity || !mvtForm.data.stock_movement.storage_location_id}
              >
                {t('Record movement')}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation */}
      <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('Delete this part?')}</AlertDialogTitle>
            <AlertDialogDescription>
              {part && tx('{part} will be removed along with its stock records. Parts with recorded movements cannot be deleted.', {
                part: <span className="font-mono font-semibold text-foreground">{partRef(part)}</span>,
              })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('Cancel')}</AlertDialogCancel>
            <AlertDialogAction onClick={confirmDelete} className="bg-destructive text-white hover:bg-destructive/90">
              {t('Delete')}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Edit Part modal — options come from the fetched detail payload. */}
      {part && (
        <PrintLabelsDialog
          open={labelOpen}
          onOpenChange={setLabelOpen}
          count={1}
          loadItems={() => Promise.resolve([labelForPart(part)])}
          title={t('Print the label for {name}', { name: part.name })}
        />
      )}

      <EditPartDialog
        partId={editOpen ? partId : null}
        open={editOpen}
        onOpenChange={(next) => {
          setEditOpen(next)
          if (!next) load()
        }}
        categories={payload?.categories ?? []}
        footprints={payload?.footprints ?? []}
        suppliers={payload?.suppliers ?? []}
        tags={payload?.tags ?? []}
        supplierLookupEnabled={payload?.supplier_lookup_enabled ?? false}
        ipnManualEntry={payload?.ipn_manual_entry ?? false}
      />
    </>
  )
}

function ConsumptionBlock({ consumption, threshold, canWrite, onApply }: {
  consumption: ConsumptionEntry
  threshold: number
  canWrite: boolean
  onApply: () => void
}) {
  const peak = Math.max(...consumption.months.map((m) => m.quantity), 1)
  const suggested = consumption.suggested_threshold

  return (
    <div>
      <div className="mb-2 flex items-center justify-between">
        <h3 className="text-sm font-semibold">{t('Consumption')}</h3>
        <span className="text-xs text-muted-foreground">{t('last {days} days', { days: consumption.window_days })}</span>
      </div>
      {consumption.consumed === 0 && consumption.months.every((m) => m.quantity === 0) ? (
        <p className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">
          {t('No use recorded yet. Builds, scanner and manual stock-outs count; moves and loans don’t.')}
        </p>
      ) : (
        <div className="space-y-3 rounded-lg border p-3">
          <div className="grid grid-cols-3 gap-2 text-center">
            {[
              { label: t('Used'), value: consumption.consumed.toLocaleString(intlLocale()) },
              { label: t('Per month'), value: consumption.monthly_rate.toLocaleString(intlLocale(), { maximumFractionDigits: 1 }) },
              { label: t('Stock lasts'), value: consumption.days_left != null ? tn('{count} day', '{count} days', consumption.days_left) : '—' },
            ].map((stat) => (
              <div key={stat.label}>
                <div className="text-xs text-muted-foreground">{stat.label}</div>
                <div className="font-mono text-sm font-semibold">{stat.value}</div>
              </div>
            ))}
          </div>
          <div className="flex items-end gap-1.5" aria-label={t('Units used per month')}>
            {consumption.months.map((m) => (
              <div key={m.month} className="flex flex-1 flex-col items-center gap-1" title={`${m.quantity}`}>
                <div className="flex h-12 w-full items-end">
                  <div
                    className="w-full rounded-sm bg-primary/70"
                    style={{ height: `${m.quantity > 0 ? Math.max((m.quantity / peak) * 100, 4) : 0}%` }}
                  />
                </div>
                <span className="text-[10px] text-muted-foreground">
                  {new Date(`${m.month}-01T00:00:00`).toLocaleDateString(intlLocale(), { month: 'short' })}
                </span>
              </div>
            ))}
          </div>
          <div className="flex items-center justify-between gap-2 border-t pt-3 text-sm">
            {suggested != null ? (
              <>
                <span className="text-muted-foreground">
                  {tx('Suggested threshold {value}', { value: <span className="font-mono font-semibold text-foreground">{suggested}</span> })}
                  <span className="block text-xs">{tn('Covers {count} day of use', 'Covers {count} days of use', consumption.cover_days ?? 0)}</span>
                </span>
                {canWrite && suggested !== threshold && (
                  <Button variant="outline" size="sm" onClick={onApply}>{t('Use {value}', { value: suggested })}</Button>
                )}
              </>
            ) : (
              <span className="text-xs text-muted-foreground">{t('Not enough uses yet to suggest a threshold.')}</span>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
