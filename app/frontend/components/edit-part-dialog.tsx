import { useForm } from '@inertiajs/react'
import { FormEvent, ReactNode, useEffect, useState } from 'react'
import { ChevronRight, CircleAlert, Loader2, Plus, Trash2, Star } from 'lucide-react'

import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Checkbox } from '@/components/ui/checkbox'
import { Badge } from '@/components/ui/badge'
import { CategorySelect } from '@/components/category-select'
import { TagPicker } from '@/components/tag-picker'
import { SupplierLookup, LookupResult, matchProviderSupplier } from '@/components/supplier-lookup'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'
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
  website?: string | null
  catalog_provider?: string | null
}

interface Tag {
  id: number
  name: string
  color: string | null
}

interface PartSupplier {
  id: number
  supplier_id: number
  supplier_name: string
  supplier_sku: string | null
  unit_price: number | null
  lead_time_days: number | null
  url: string | null
  is_preferred: boolean
  notes: string | null
}

// The full part payload fetched from GET /parts/:id/edit (JSON).
interface FullPart {
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
  status: string
  unit_price: number | null
  min_stock_threshold: number
  target_stock: number | null
  rohs_compliant: boolean
  storage_notes: string | null
  category_id: number
  footprint_id: number | null
  tag_ids: number[]
  part_suppliers: PartSupplier[]
}

// A supplier row while editing. Existing links carry their `id` (so the server
// updates rather than recreates); newly added ones leave it undefined.
interface PendingSupplier {
  tempId: string
  id?: number
  supplier_id: string
  supplier_name: string
  supplier_sku: string
  unit_price: string
  lead_time_days: string
  url: string
  is_preferred: boolean
  notes: string
}

interface EditPartDialogProps {
  partId: number | null
  open: boolean
  onOpenChange: (open: boolean) => void
  categories: Category[]
  footprints: Footprint[]
  suppliers: Supplier[]
  tags: Tag[]
  supplierLookupEnabled?: boolean
}

const EMPTY_SUPPLIER = {
  supplier_id: '',
  supplier_sku: '',
  unit_price: '',
  lead_time_days: '',
  url: '',
  is_preferred: false,
  notes: '',
}

// Turns a (possibly dotted, nested) error key into a readable label, e.g.
// 'part.min_stock_threshold' -> 'Min Stock Threshold'.
function fieldLabel(key: string): string {
  const name = key.includes('.') ? key.split('.').pop()! : key
  return name
    .replace(/_/g, ' ')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/\b\w/g, (char) => char.toUpperCase())
}

// Lightweight disclosure section — mirrors the add-part dialog (no Radix
// Collapsible in the library, so a button + conditional render).
function Section({
  title,
  description,
  open,
  onToggle,
  children,
}: {
  title: string
  description: string
  open: boolean
  onToggle: () => void
  children: ReactNode
}) {
  return (
    <div className="rounded-lg border">
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full items-center gap-2 px-4 py-3 text-left"
      >
        <ChevronRight className={`size-4 shrink-0 text-muted-foreground transition-transform ${open ? 'rotate-90' : ''}`} />
        <span className="flex-1">
          <span className="block text-sm font-medium">{title}</span>
          <span className="block text-xs text-muted-foreground">{description}</span>
        </span>
      </button>
      {open && <div className="border-t px-4 py-4">{children}</div>}
    </div>
  )
}

// Maps the fetched part into the flat, all-strings shape the form fields use.
function toFormPart(part: FullPart) {
  return {
    name: part.name,
    mpn: part.mpn || '',
    sku: part.sku || '',
    barcode: part.barcode || '',
    manufacturer: part.manufacturer || '',
    description: part.description || '',
    value: part.value || '',
    tolerance: part.tolerance || '',
    voltage_rating: part.voltage_rating || '',
    power_rating: part.power_rating || '',
    package_type: part.package_type || '',
    category_id: part.category_id.toString(),
    footprint_id: part.footprint_id?.toString() || '',
    unit_price: part.unit_price?.toString() || '',
    min_stock_threshold: part.min_stock_threshold.toString(),
    target_stock: part.target_stock?.toString() || '',
    status: part.status,
    rohs_compliant: part.rohs_compliant,
    storage_notes: part.storage_notes || '',
    tag_ids: part.tag_ids,
  }
}

const EMPTY_PART = toFormPart({
  id: 0,
  name: '',
  mpn: null,
  sku: null,
  barcode: null,
  manufacturer: null,
  description: null,
  value: null,
  tolerance: null,
  voltage_rating: null,
  power_rating: null,
  package_type: null,
  status: 'active',
  unit_price: null,
  min_stock_threshold: 0,
  target_stock: null,
  rohs_compliant: false,
  storage_notes: null,
  category_id: 0,
  footprint_id: null,
  tag_ids: [],
  part_suppliers: [],
})

export function EditPartDialog({
  partId,
  open,
  onOpenChange,
  categories,
  footprints,
  suppliers,
  tags,
  supplierLookupEnabled = false,
}: EditPartDialogProps) {
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState('')
  const [detailsOpen, setDetailsOpen] = useState(false)
  const [suppliersOpen, setSuppliersOpen] = useState(false)
  const [pendingSuppliers, setPendingSuppliers] = useState<PendingSupplier[]>([])
  // Ids of existing part-supplier links the user removed — sent back as
  // `_destroy` so the server tears them down.
  const [removedSupplierIds, setRemovedSupplierIds] = useState<number[]>([])
  const [newSupplier, setNewSupplier] = useState({ ...EMPTY_SUPPLIER })

  // Datasheet/image URLs from a chosen catalog match, downloaded + attached
  // server-side on save.
  const [attach, setAttach] = useState<{ datasheet_url: string | null; image_url: string | null }>({
    datasheet_url: null,
    image_url: null,
  })

  const form = useForm({ part: { ...EMPTY_PART } })
  const { data, setData, errors } = form

  // A flat, human-readable list of every validation error so nothing is hidden —
  // fields living inside collapsed sections would otherwise show no error.
  const errorMessages = Object.entries(errors).map(([key, message]) =>
    key.endsWith('.base') ? String(message) : `${fieldLabel(key)} ${message}`
  )

  // Expand any collapsed section that contains an error so its inline message is
  // actually visible when the server rejects the submission.
  useEffect(() => {
    const keys = Object.keys(errors)
    if (keys.some((k) => ['part.mpn', 'part.sku'].includes(k))) setDetailsOpen(true)
    if (keys.some((k) => k.includes('part_suppliers'))) setSuppliersOpen(true)
  }, [errors])

  // Load the full part when the dialog opens, then seed the form + suppliers.
  useEffect(() => {
    if (!open || partId == null) return
    let cancelled = false
    setLoading(true)
    setLoadError('')
    fetch(`/parts/${partId}/edit`, { headers: { Accept: 'application/json' } })
      .then((res) => {
        if (!res.ok) throw new Error('Failed to load part')
        return res.json()
      })
      .then((body: { part: FullPart }) => {
        if (cancelled) return
        const part = body.part
        setData('part', toFormPart(part))
        setPendingSuppliers(
          part.part_suppliers.map((ps) => ({
            tempId: crypto.randomUUID(),
            id: ps.id,
            supplier_id: ps.supplier_id.toString(),
            supplier_name: ps.supplier_name,
            supplier_sku: ps.supplier_sku || '',
            unit_price: ps.unit_price?.toString() || '',
            lead_time_days: ps.lead_time_days?.toString() || '',
            url: ps.url || '',
            is_preferred: ps.is_preferred,
            notes: ps.notes || '',
          }))
        )
        setLoading(false)
      })
      .catch(() => {
        if (cancelled) return
        setLoadError('Could not load this part. Please try again.')
        setLoading(false)
      })
    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, partId])

  // Fold the suppliers (as nested attributes) and catalog asset URLs into the
  // payload right before it goes over the wire.
  form.transform((payload) => ({
    ...payload,
    datasheet_url: attach.datasheet_url,
    image_url: attach.image_url,
    part: {
      ...payload.part,
      part_suppliers_attributes: [
        ...pendingSuppliers.map((ps) => ({
          id: ps.id,
          supplier_id: ps.supplier_id,
          supplier_sku: ps.supplier_sku || null,
          unit_price: ps.unit_price || null,
          lead_time_days: ps.lead_time_days || null,
          url: ps.url || null,
          is_preferred: ps.is_preferred,
          notes: ps.notes || null,
        })),
        ...removedSupplierIds.map((id) => ({ id, _destroy: true })),
      ],
    },
  }))

  const setPart = (patch: Partial<typeof EMPTY_PART>) => setData('part', { ...data.part, ...patch })

  const resetLocal = () => {
    form.clearErrors()
    setPendingSuppliers([])
    setRemovedSupplierIds([])
    setNewSupplier({ ...EMPTY_SUPPLIER })
    setDetailsOpen(false)
    setSuppliersOpen(false)
    setAttach({ datasheet_url: null, image_url: null })
    setLoadError('')
  }

  // Prefill the form from a chosen catalog match. Only overwrites fields the
  // result actually provides, leaving anything already entered intact.
  const applyResult = (result: LookupResult) => {
    setPart({
      name: result.name || data.part.name,
      mpn: result.mpn || data.part.mpn,
      manufacturer: result.manufacturer || data.part.manufacturer,
      description: result.description || data.part.description,
      value: result.value || data.part.value,
      package_type: result.package_type || data.part.package_type,
      tolerance: result.tolerance || data.part.tolerance,
      voltage_rating: result.voltage_rating || data.part.voltage_rating,
      power_rating: result.power_rating || data.part.power_rating,
      unit_price: result.unit_price || data.part.unit_price,
      rohs_compliant: result.rohs_compliant || data.part.rohs_compliant,
    })
    setAttach({ datasheet_url: result.datasheet_url, image_url: result.image_url })
    setDetailsOpen(true)
    applySupplierFromResult(result)
  }

  // Pre-fill the Suppliers section from a catalog match: link the provider's own
  // supplier (Mouser/DigiKey) with the fetched price, SKU and product URL. Only
  // runs when that supplier exists in the org and the result carries data;
  // re-running a lookup refreshes the existing row instead of duplicating it.
  const applySupplierFromResult = (result: LookupResult) => {
    const supplier = matchProviderSupplier(suppliers, result.provider)
    if (!supplier) return
    if (!result.unit_price && !result.supplier_sku && !result.product_url) return

    const supplierId = supplier.id.toString()
    setPendingSuppliers((prev) => {
      const existing = prev.find((ps) => ps.supplier_id === supplierId)
      if (existing) {
        return prev.map((ps) =>
          ps.supplier_id === supplierId
            ? {
                ...ps,
                supplier_sku: result.supplier_sku || ps.supplier_sku,
                unit_price: result.unit_price || ps.unit_price,
                url: result.product_url || ps.url,
              }
            : ps
        )
      }
      return [
        ...prev,
        {
          tempId: crypto.randomUUID(),
          supplier_id: supplierId,
          supplier_name: supplier.name,
          supplier_sku: result.supplier_sku || '',
          unit_price: result.unit_price || '',
          lead_time_days: '',
          url: result.product_url || '',
          is_preferred: prev.length === 0,
          notes: '',
        },
      ]
    })
    setSuppliersOpen(true)
  }

  const handleOpenChange = (next: boolean) => {
    if (!next) resetLocal()
    onOpenChange(next)
  }

  const submit = (e: FormEvent) => {
    e.preventDefault()
    if (partId == null) return
    form.put(`/parts/${partId}`, {
      preserveScroll: true,
      preserveState: true,
      onSuccess: () => {
        resetLocal()
        onOpenChange(false)
      },
    })
  }

  const availableSuppliers = suppliers.filter(
    (s) => !pendingSuppliers.some((ps) => ps.supplier_id === s.id.toString())
  )

  const addPendingSupplier = () => {
    const supplier = suppliers.find((s) => s.id.toString() === newSupplier.supplier_id)
    if (!supplier) return
    const others = newSupplier.is_preferred
      ? pendingSuppliers.map((ps) => ({ ...ps, is_preferred: false }))
      : pendingSuppliers
    setPendingSuppliers([
      ...others,
      { ...newSupplier, tempId: crypto.randomUUID(), supplier_name: supplier.name },
    ])
    setNewSupplier({ ...EMPTY_SUPPLIER })
  }

  const removePendingSupplier = (ps: PendingSupplier) => {
    setPendingSuppliers(pendingSuppliers.filter((p) => p.tempId !== ps.tempId))
    if (ps.id != null) setRemovedSupplierIds((ids) => [...ids, ps.id!])
  }

  const setPreferred = (tempId: string) =>
    setPendingSuppliers(pendingSuppliers.map((ps) => ({ ...ps, is_preferred: ps.tempId === tempId })))

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="flex max-h-[90svh] flex-col gap-0 p-0 sm:max-w-2xl lg:max-w-4xl">
        <DialogHeader className="border-b px-6 py-4">
          <DialogTitle>Edit part</DialogTitle>
          <DialogDescription>
            Update the essentials — expand the sections below for more detail.
          </DialogDescription>
        </DialogHeader>

        {loading ? (
          <div className="flex flex-1 items-center justify-center py-16">
            <Loader2 className="size-6 animate-spin text-muted-foreground" />
          </div>
        ) : loadError ? (
          <div className="flex flex-1 flex-col items-center justify-center gap-4 px-6 py-16">
            <Alert variant="destructive">
              <CircleAlert />
              <AlertDescription>{loadError}</AlertDescription>
            </Alert>
            <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>Close</Button>
          </div>
        ) : (
          <form onSubmit={submit} className="flex min-h-0 flex-1 flex-col">
            <div className="@container min-h-0 flex-1 space-y-5 overflow-y-auto px-6 py-5">
              {/* Validation summary — keeps errors inside the modal and surfaces
                  those in collapsed sections. */}
              {errorMessages.length > 0 && (
                <Alert variant="destructive">
                  <CircleAlert />
                  <AlertDescription>
                    {errorMessages.length === 1 ? (
                      errorMessages[0]
                    ) : (
                      <ul className="list-inside list-disc space-y-1">
                        {errorMessages.map((msg, i) => (
                          <li key={i}>{msg}</li>
                        ))}
                      </ul>
                    )}
                  </AlertDescription>
                </Alert>
              )}

              {/* Supplier catalog lookup */}
              {supplierLookupEnabled && (
                <SupplierLookup
                  defaultQuery={data.part.mpn}
                  onApply={applyResult}
                  attached={{ datasheet: !!attach.datasheet_url, image: !!attach.image_url }}
                />
              )}

              {/* Essentials */}
              <div className="grid grid-cols-2 gap-4 @2xl:grid-cols-4">
                <Field className="col-span-2 @2xl:col-span-4">
                  <FieldLabel>
                    <Label>Name *</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      placeholder="e.g. Resistor 10k 1% 0603"
                      value={data.part.name}
                      onChange={(e) => setPart({ name: e.target.value })}
                      autoFocus
                    />
                  </FieldContent>
                  {errors['part.name'] && <FieldError>{errors['part.name']}</FieldError>}
                </Field>
                <Field className="col-span-2 @2xl:col-span-4">
                  <FieldLabel>
                    <Label>Category *</Label>
                  </FieldLabel>
                  <FieldContent>
                    <CategorySelect
                      categories={categories}
                      value={data.part.category_id}
                      onValueChange={(value) => setPart({ category_id: value })}
                    />
                  </FieldContent>
                  {errors['part.category_id'] && <FieldError>{errors['part.category_id']}</FieldError>}
                </Field>
                <Field>
                  <FieldLabel>
                    <Label>Value</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      placeholder="e.g. 10 kΩ"
                      value={data.part.value}
                      onChange={(e) => setPart({ value: e.target.value })}
                    />
                  </FieldContent>
                </Field>
                <Field>
                  <FieldLabel>
                    <Label>Package</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      placeholder="e.g. 0603"
                      value={data.part.package_type}
                      onChange={(e) => setPart({ package_type: e.target.value })}
                    />
                  </FieldContent>
                </Field>
                <Field>
                  <FieldLabel>
                    <Label>Min. threshold</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      inputMode="numeric"
                      value={data.part.min_stock_threshold}
                      onChange={(e) => setPart({ min_stock_threshold: e.target.value.replace(/[^0-9]/g, '') })}
                    />
                  </FieldContent>
                  {errors['part.min_stock_threshold'] && <FieldError>{errors['part.min_stock_threshold']}</FieldError>}
                </Field>
                <Field>
                  <FieldLabel>
                    <Label>Unit price</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      placeholder="0.00"
                      value={data.part.unit_price}
                      onChange={(e) => setPart({ unit_price: e.target.value })}
                    />
                  </FieldContent>
                  <p className="text-xs text-muted-foreground">Auto-set from your preferred supplier's price on save.</p>
                  {errors['part.unit_price'] && <FieldError>{errors['part.unit_price']}</FieldError>}
                </Field>
              </div>

              {/* More details */}
              <Section
                title="More details"
                description="Identifiers, classification, specifications"
                open={detailsOpen}
                onToggle={() => setDetailsOpen((v) => !v)}
              >
                <div className="grid grid-cols-2 gap-4 @2xl:grid-cols-4">
                  <Field>
                    <FieldLabel>
                      <Label>MPN</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Input
                        placeholder="e.g. RC0805FR-0710KL"
                        value={data.part.mpn}
                        onChange={(e) => setPart({ mpn: e.target.value })}
                      />
                    </FieldContent>
                    {errors['part.mpn'] && <FieldError>{errors['part.mpn']}</FieldError>}
                  </Field>
                  <Field>
                    <FieldLabel>
                      <Label>Internal SKU</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Input
                        placeholder="e.g. RES-10K-0805"
                        value={data.part.sku}
                        onChange={(e) => setPart({ sku: e.target.value })}
                      />
                    </FieldContent>
                    {errors['part.sku'] && <FieldError>{errors['part.sku']}</FieldError>}
                  </Field>
                  <Field>
                    <FieldLabel>
                      <Label>Barcode</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Input
                        placeholder="Scan or enter barcode"
                        value={data.part.barcode}
                        onChange={(e) => setPart({ barcode: e.target.value })}
                      />
                    </FieldContent>
                  </Field>
                  <Field>
                    <FieldLabel>
                      <Label>Manufacturer</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Input
                        placeholder="e.g. Yageo"
                        value={data.part.manufacturer}
                        onChange={(e) => setPart({ manufacturer: e.target.value })}
                      />
                    </FieldContent>
                  </Field>
                  <Field className="col-span-2 @2xl:col-span-4">
                    <FieldLabel>
                      <Label>Description</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Textarea
                        rows={2}
                        placeholder="Detailed description of the part"
                        value={data.part.description}
                        onChange={(e) => setPart({ description: e.target.value })}
                      />
                    </FieldContent>
                  </Field>
                  <Field>
                    <FieldLabel>
                      <Label>Footprint</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Select
                        value={data.part.footprint_id || 'none'}
                        onValueChange={(value) => setPart({ footprint_id: value === 'none' ? '' : value })}
                      >
                        <SelectTrigger className="w-full">
                          <SelectValue placeholder="Select a footprint" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="none">None</SelectItem>
                          {footprints.map((footprint) => (
                            <SelectItem key={footprint.id} value={footprint.id.toString()}>
                              {footprint.name}
                              {footprint.mounting_type && ` (${footprint.mounting_type})`}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </FieldContent>
                  </Field>
                  <Field>
                    <FieldLabel>
                      <Label>Status</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Select
                        value={data.part.status}
                        onValueChange={(value) => setPart({ status: value })}
                      >
                        <SelectTrigger className="w-full">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="active">Active</SelectItem>
                          <SelectItem value="discontinued">Discontinued</SelectItem>
                          <SelectItem value="obsolete">Obsolete</SelectItem>
                        </SelectContent>
                      </Select>
                    </FieldContent>
                  </Field>
                  <Field className="col-span-2 @2xl:col-span-4">
                    <FieldLabel>
                      <Label>Tags</Label>
                    </FieldLabel>
                    <FieldContent>
                      <TagPicker
                        tags={tags}
                        value={data.part.tag_ids}
                        onChange={(ids) => setPart({ tag_ids: ids })}
                      />
                    </FieldContent>
                  </Field>
                  <Field>
                    <FieldLabel>
                      <Label>Tolerance</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Input
                        placeholder="e.g. 1%, 5%"
                        value={data.part.tolerance}
                        onChange={(e) => setPart({ tolerance: e.target.value })}
                      />
                    </FieldContent>
                  </Field>
                  <Field>
                    <FieldLabel>
                      <Label>Voltage rating</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Input
                        placeholder="e.g. 50V"
                        value={data.part.voltage_rating}
                        onChange={(e) => setPart({ voltage_rating: e.target.value })}
                      />
                    </FieldContent>
                  </Field>
                  <Field>
                    <FieldLabel>
                      <Label>Power rating</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Input
                        placeholder="e.g. 0.125W"
                        value={data.part.power_rating}
                        onChange={(e) => setPart({ power_rating: e.target.value })}
                      />
                    </FieldContent>
                  </Field>
                  <Field>
                    <FieldLabel>
                      <Label>Target stock</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Input
                        inputMode="numeric"
                        placeholder="e.g. 100"
                        value={data.part.target_stock}
                        onChange={(e) => setPart({ target_stock: e.target.value.replace(/[^0-9]/g, '') })}
                      />
                    </FieldContent>
                  </Field>
                  <Field className="col-span-2 @2xl:col-span-4">
                    <FieldLabel>
                      <Label>Storage notes</Label>
                    </FieldLabel>
                    <FieldContent>
                      <Textarea
                        rows={2}
                        placeholder="Special storage or handling instructions"
                        value={data.part.storage_notes}
                        onChange={(e) => setPart({ storage_notes: e.target.value })}
                      />
                    </FieldContent>
                  </Field>
                  <Field className="col-span-2 @2xl:col-span-4">
                    <div className="flex items-center space-x-2">
                      <Checkbox
                        id="edit_rohs_compliant"
                        checked={data.part.rohs_compliant}
                        onCheckedChange={(checked) => setPart({ rohs_compliant: checked === true })}
                      />
                      <Label htmlFor="edit_rohs_compliant" className="cursor-pointer font-normal">
                        RoHS compliant
                      </Label>
                    </div>
                  </Field>
                </div>
              </Section>

              {/* Suppliers */}
              <Section
                title="Suppliers"
                description={pendingSuppliers.length > 0 ? `${pendingSuppliers.length} linked` : 'Link suppliers (optional)'}
                open={suppliersOpen}
                onToggle={() => setSuppliersOpen((v) => !v)}
              >
                {pendingSuppliers.length > 0 && (
                  <div className="mb-4 overflow-hidden rounded-md border">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Supplier</TableHead>
                          <TableHead>SKU</TableHead>
                          <TableHead className="text-right">Price</TableHead>
                          <TableHead>Status</TableHead>
                          <TableHead className="w-[80px]" />
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {pendingSuppliers.map((ps) => (
                          <TableRow key={ps.tempId}>
                            <TableCell className="font-medium">{ps.supplier_name}</TableCell>
                            <TableCell>{ps.supplier_sku || '-'}</TableCell>
                            <TableCell className="text-right font-mono">
                              {ps.unit_price ? `$${parseFloat(ps.unit_price).toFixed(2)}` : '-'}
                            </TableCell>
                            <TableCell>
                              {ps.is_preferred && (
                                <Badge variant="default">
                                  <Star className="mr-1 size-3" />
                                  Preferred
                                </Badge>
                              )}
                            </TableCell>
                            <TableCell>
                              <div className="flex items-center gap-1">
                                {!ps.is_preferred && (
                                  <Button type="button" variant="ghost" size="icon" onClick={() => setPreferred(ps.tempId)} title="Set as preferred">
                                    <Star className="size-4" />
                                  </Button>
                                )}
                                <Button type="button" variant="ghost" size="icon" onClick={() => removePendingSupplier(ps)} title="Remove supplier">
                                  <Trash2 className="size-4 text-destructive" />
                                </Button>
                              </div>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>
                )}

                {availableSuppliers.length > 0 ? (
                  <div className="grid grid-cols-2 gap-3">
                    <div className="col-span-2 grid grid-cols-2 gap-3 sm:grid-cols-4">
                      <div className="col-span-2 space-y-1.5">
                        <Label className="text-xs">Supplier</Label>
                        <Select
                          value={newSupplier.supplier_id}
                          onValueChange={(value) => setNewSupplier({ ...newSupplier, supplier_id: value })}
                        >
                          <SelectTrigger className="w-full">
                            <SelectValue placeholder="Select supplier" />
                          </SelectTrigger>
                          <SelectContent>
                            {availableSuppliers.map((supplier) => (
                              <SelectItem key={supplier.id} value={supplier.id.toString()}>{supplier.name}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="space-y-1.5">
                        <Label className="text-xs">SKU</Label>
                        <Input
                          value={newSupplier.supplier_sku}
                          onChange={(e) => setNewSupplier({ ...newSupplier, supplier_sku: e.target.value })}
                        />
                      </div>
                      <div className="space-y-1.5">
                        <Label className="text-xs">Price</Label>
                        <Input
                          type="number"
                          step="0.01"
                          min="0"
                          value={newSupplier.unit_price}
                          onChange={(e) => setNewSupplier({ ...newSupplier, unit_price: e.target.value })}
                        />
                      </div>
                    </div>
                    <div className="col-span-2 flex items-center justify-between">
                      <label className="flex items-center gap-2 text-sm">
                        <Checkbox
                          checked={newSupplier.is_preferred}
                          onCheckedChange={(checked) => setNewSupplier({ ...newSupplier, is_preferred: checked === true })}
                        />
                        Preferred supplier
                      </label>
                      <Button type="button" size="sm" variant="outline" onClick={addPendingSupplier} disabled={!newSupplier.supplier_id}>
                        <Plus className="size-4" />
                        Add supplier
                      </Button>
                    </div>
                  </div>
                ) : (
                  <p className="text-sm text-muted-foreground">
                    {suppliers.length === 0 ? 'No suppliers exist yet.' : 'All suppliers already linked.'}
                  </p>
                )}
              </Section>
            </div>

            <DialogFooter className="border-t px-6 py-4">
              <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>Cancel</Button>
              <Button type="submit" disabled={form.processing}>Save changes</Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  )
}
