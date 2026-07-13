import { useForm } from '@inertiajs/react'
import { FormEvent, ReactNode, useState } from 'react'
import { ChevronRight, Plus, Trash2, Star } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Checkbox } from '@/components/ui/checkbox'
import { Badge } from '@/components/ui/badge'
import { CategorySelect } from '@/components/category-select'
import { TagPicker } from '@/components/tag-picker'
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
}

interface Tag {
  id: number
  name: string
  color: string | null
}

interface StorageLocationOption {
  id: number
  name: string
}

interface PendingSupplier {
  tempId: string
  supplier_id: string
  supplier_name: string
  supplier_sku: string
  unit_price: string
  lead_time_days: string
  url: string
  is_preferred: boolean
  notes: string
}

interface AddPartDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  categories: Category[]
  footprints: Footprint[]
  suppliers: Supplier[]
  tags: Tag[]
  storageLocations: StorageLocationOption[]
}

const EMPTY_PART = {
  name: '',
  mpn: '',
  sku: '',
  barcode: '',
  manufacturer: '',
  description: '',
  value: '',
  tolerance: '',
  voltage_rating: '',
  power_rating: '',
  package_type: '',
  category_id: '',
  footprint_id: '',
  unit_price: '',
  min_stock_threshold: '0',
  target_stock: '',
  status: 'active',
  rohs_compliant: false,
  storage_notes: '',
  tag_ids: [] as number[],
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

// Lightweight disclosure section — no Radix Collapsible in the library, so a
// button + conditional render (same pattern the parts form already uses).
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

export function AddPartDialog({
  open,
  onOpenChange,
  categories,
  footprints,
  suppliers,
  tags,
  storageLocations,
}: AddPartDialogProps) {
  const [detailsOpen, setDetailsOpen] = useState(false)
  const [suppliersOpen, setSuppliersOpen] = useState(false)
  const [pendingSuppliers, setPendingSuppliers] = useState<PendingSupplier[]>([])
  const [newSupplier, setNewSupplier] = useState({ ...EMPTY_SUPPLIER })

  const form = useForm({
    part: { ...EMPTY_PART },
    initial_location_id: '',
    initial_quantity: '',
  })
  const { data, setData, errors } = form

  // Fold the pending suppliers into the payload right before it goes over the wire.
  form.transform((payload) => ({
    ...payload,
    part: {
      ...payload.part,
      part_suppliers_attributes: pendingSuppliers.map((ps) => ({
        supplier_id: ps.supplier_id,
        supplier_sku: ps.supplier_sku || null,
        unit_price: ps.unit_price || null,
        lead_time_days: ps.lead_time_days || null,
        url: ps.url || null,
        is_preferred: ps.is_preferred,
        notes: ps.notes || null,
      })),
    },
  }))

  const setPart = (patch: Partial<typeof EMPTY_PART>) => setData('part', { ...data.part, ...patch })

  const resetAll = () => {
    form.reset()
    form.clearErrors()
    setPendingSuppliers([])
    setNewSupplier({ ...EMPTY_SUPPLIER })
    setDetailsOpen(false)
    setSuppliersOpen(false)
  }

  const handleOpenChange = (next: boolean) => {
    if (!next) resetAll()
    onOpenChange(next)
  }

  const submit = (e: FormEvent) => {
    e.preventDefault()
    form.post('/parts', {
      preserveScroll: true,
      preserveState: true,
      onSuccess: () => {
        resetAll()
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

  const removePendingSupplier = (tempId: string) =>
    setPendingSuppliers(pendingSuppliers.filter((ps) => ps.tempId !== tempId))

  const setPreferred = (tempId: string) =>
    setPendingSuppliers(pendingSuppliers.map((ps) => ({ ...ps, is_preferred: ps.tempId === tempId })))

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="flex max-h-[90svh] flex-col gap-0 p-0 sm:max-w-2xl">
        <DialogHeader className="border-b px-6 py-4">
          <DialogTitle>Add part</DialogTitle>
          <DialogDescription>
            Fill in the essentials — expand the sections below for more detail.
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={submit} className="flex min-h-0 flex-1 flex-col">
          <div className="min-h-0 flex-1 space-y-5 overflow-y-auto px-6 py-5">
            {/* Essentials */}
            <div className="grid grid-cols-2 gap-4">
              <Field className="col-span-2">
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
              <Field className="col-span-2">
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
                  <Label>Initial location</Label>
                </FieldLabel>
                <FieldContent>
                  <Select
                    value={data.initial_location_id || 'none'}
                    onValueChange={(value) => setData('initial_location_id', value === 'none' ? '' : value)}
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="No location" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">No location</SelectItem>
                      {storageLocations.map((location) => (
                        <SelectItem key={location.id} value={location.id.toString()}>{location.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FieldContent>
              </Field>
              <Field>
                <FieldLabel>
                  <Label>Quantity</Label>
                </FieldLabel>
                <FieldContent>
                  <Input
                    inputMode="numeric"
                    placeholder="0"
                    disabled={!data.initial_location_id}
                    value={data.initial_quantity}
                    onChange={(e) => setData('initial_quantity', e.target.value.replace(/[^0-9]/g, ''))}
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
              <div className="grid grid-cols-2 gap-4">
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
                <Field className="col-span-2">
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
                <Field className="col-span-2">
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
                <Field className="col-span-2">
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
                <Field className="col-span-2">
                  <div className="flex items-center space-x-2">
                    <Checkbox
                      id="add_rohs_compliant"
                      checked={data.part.rohs_compliant}
                      onCheckedChange={(checked) => setPart({ rohs_compliant: checked === true })}
                    />
                    <Label htmlFor="add_rohs_compliant" className="cursor-pointer font-normal">
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
                              <Button type="button" variant="ghost" size="icon" onClick={() => removePendingSupplier(ps.tempId)} title="Remove supplier">
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
            <Button type="submit" disabled={form.processing}>Add part</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
