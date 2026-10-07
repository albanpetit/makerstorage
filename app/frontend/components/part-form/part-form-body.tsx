import { ReactNode, useEffect } from 'react'
import { ChevronRight, CircleAlert, ImagePlus, Plus, Trash2, Star, X } from 'lucide-react'

import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Checkbox } from '@/components/ui/checkbox'
import { Badge } from '@/components/ui/badge'
import { CategorySelect } from '@/components/category-select'
import { TagPicker } from '@/components/tag-picker'
import { SupplierLookup, LookupResult } from '@/components/supplier-lookup'
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

import { PartSuppliersController } from './use-part-suppliers'
import {
  Category,
  fieldLabel,
  Footprint,
  PartFormData,
  StorageLocationOption,
  Tag,
} from './types'

// Lightweight disclosure section — no Radix Collapsible in the library, so a
// button + conditional render.
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

export interface PartFormBodyProps {
  mode: 'add' | 'edit'
  part: PartFormData
  setPart: (patch: Partial<PartFormData>) => void
  errors: Record<string, string>

  categories: Category[]
  footprints: Footprint[]
  tags: Tag[]

  ipnManualEntry: boolean

  // Supplier catalog lookup
  supplierLookupEnabled: boolean
  onApplyLookup: (result: LookupResult) => void
  attach: { datasheet_url: string | null; image_url: string | null }

  // Image upload
  imagePreview: string | null
  imageFile: File | null
  onImageFileChange: (file: File | null) => void

  // Collapsible sections
  detailsOpen: boolean
  setDetailsOpen: (updater: (v: boolean) => boolean) => void
  suppliersOpen: boolean
  setSuppliersOpen: (updater: (v: boolean) => boolean) => void

  // Supplier management (shared hook)
  suppliersController: PartSuppliersController
  allSuppliers: { length: number }

  // Add-only initial stock fields
  storageLocations?: StorageLocationOption[]
  initialLocationId?: string
  initialQuantity?: string
  onInitialLocationChange?: (value: string) => void
  onInitialQuantityChange?: (value: string) => void
}

// The scrollable body shared by the add- and edit-part dialogs: the validation
// summary, catalog lookup, essentials grid, "More details" and "Suppliers"
// sections. The dialogs own the surrounding shell, form state, and submit/reset.
export function PartFormBody({
  mode,
  part,
  setPart,
  errors,
  categories,
  footprints,
  tags,
  ipnManualEntry,
  supplierLookupEnabled,
  onApplyLookup,
  attach,
  imagePreview,
  imageFile,
  onImageFileChange,
  detailsOpen,
  setDetailsOpen,
  suppliersOpen,
  setSuppliersOpen,
  suppliersController,
  allSuppliers,
  storageLocations,
  initialLocationId,
  initialQuantity,
  onInitialLocationChange,
  onInitialQuantityChange,
}: PartFormBodyProps) {
  const {
    pendingSuppliers,
    newSupplier,
    setNewSupplier,
    availableSuppliers,
    addPendingSupplier,
    removePendingSupplier,
    setPreferred,
  } = suppliersController

  // A flat, human-readable list of every validation error so nothing is hidden —
  // fields living inside collapsed sections would otherwise show no error.
  const errorMessages = Object.entries(errors).map(([key, message]) =>
    key.endsWith('.base') ? String(message) : `${fieldLabel(key)} ${message}`
  )

  // Expand any collapsed section that contains an error so its inline message is
  // actually visible when the server rejects the submission.
  useEffect(() => {
    const keys = Object.keys(errors)
    if (keys.some((k) => ['part.mpn', 'part.sku', 'part.ipn'].includes(k))) setDetailsOpen(() => true)
    if (keys.some((k) => k.includes('part_suppliers'))) setSuppliersOpen(() => true)
  }, [errors, setDetailsOpen, setSuppliersOpen])

  const imageHelp = imageFile
    ? mode === 'add'
      ? 'Your uploaded image will be used.'
      : 'Your uploaded image will replace the current one.'
    : attach.image_url
      ? 'Using the supplier image — upload a file to override it.'
      : mode === 'add'
        ? 'Optional. PNG or JPG.'
        : 'Upload a file to replace the current image.'

  return (
    <div className="@container min-h-0 flex-1 space-y-5 overflow-y-auto px-6 py-5">
      {/* Validation summary — keeps errors inside the modal (not on the page
          behind it) and surfaces those in collapsed sections. */}
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
          defaultQuery={part.mpn}
          onApply={onApplyLookup}
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
              value={part.name}
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
              value={part.category_id}
              onValueChange={(value) => setPart({ category_id: value })}
            />
          </FieldContent>
          {errors['part.category_id'] && <FieldError>{errors['part.category_id']}</FieldError>}
        </Field>
        <Field className="col-span-2 @2xl:col-span-4">
          <FieldLabel>
            <Label>Image</Label>
          </FieldLabel>
          <FieldContent>
            <div className="flex items-center gap-3">
              <div className="flex size-16 shrink-0 items-center justify-center overflow-hidden rounded-md border bg-muted">
                {imagePreview ? (
                  <img src={imagePreview} alt="" className="size-full object-cover" />
                ) : (
                  <ImagePlus className="size-5 text-muted-foreground" />
                )}
              </div>
              <div className="flex min-w-0 flex-col gap-1.5">
                <Input
                  key={imageFile ? 'file' : 'empty'}
                  type="file"
                  accept="image/*"
                  className="cursor-pointer"
                  onChange={(e) => onImageFileChange(e.target.files?.[0] ?? null)}
                />
                <p className="text-xs text-muted-foreground">{imageHelp}</p>
                {errors['part.images'] && <FieldError>{errors['part.images']}</FieldError>}
              </div>
              {imageFile && (
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  onClick={() => onImageFileChange(null)}
                  aria-label="Remove image"
                >
                  <X className="size-4" />
                </Button>
              )}
            </div>
          </FieldContent>
        </Field>
        <Field>
          <FieldLabel>
            <Label>Value</Label>
          </FieldLabel>
          <FieldContent>
            <Input
              placeholder="e.g. 10 kΩ"
              value={part.value}
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
              value={part.package_type}
              onChange={(e) => setPart({ package_type: e.target.value })}
            />
          </FieldContent>
        </Field>
        {mode === 'add' && storageLocations && (
          <>
            <Field>
              <FieldLabel>
                <Label>Initial location</Label>
              </FieldLabel>
              <FieldContent>
                <Select
                  value={initialLocationId || 'none'}
                  onValueChange={(value) => onInitialLocationChange?.(value === 'none' ? '' : value)}
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
                  disabled={!initialLocationId}
                  value={initialQuantity}
                  onChange={(e) => onInitialQuantityChange?.(e.target.value.replace(/[^0-9]/g, ''))}
                />
              </FieldContent>
            </Field>
          </>
        )}
        <Field>
          <FieldLabel>
            <Label>Min. threshold</Label>
          </FieldLabel>
          <FieldContent>
            <Input
              inputMode="numeric"
              value={part.min_stock_threshold}
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
              value={part.unit_price}
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
                value={part.mpn}
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
                value={part.sku}
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
                value={part.barcode}
                onChange={(e) => setPart({ barcode: e.target.value })}
              />
            </FieldContent>
            {errors['part.barcode'] && <FieldError>{errors['part.barcode']}</FieldError>}
          </Field>
          {/* IPN: in add mode it only appears when the org uses manual numbering
              (auto modes stamp it on save); in edit mode it's always shown but
              read-only unless manual. */}
          {(mode === 'edit' || ipnManualEntry) && (
            <Field>
              <FieldLabel>
                <Label>Internal part number (IPN)</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  placeholder={ipnManualEntry ? 'e.g. MS-00042' : 'Assigned automatically'}
                  value={part.ipn}
                  onChange={(e) => setPart({ ipn: e.target.value })}
                  disabled={mode === 'edit' && !ipnManualEntry}
                />
              </FieldContent>
              <p className="text-xs text-muted-foreground">
                {ipnManualEntry
                  ? mode === 'add'
                    ? "Manual numbering is on — type this part's reference."
                    : 'Manual numbering is on — edit this part’s reference.'
                  : 'Generated from your numbering settings.'}
              </p>
              {errors['part.ipn'] && <FieldError>{errors['part.ipn']}</FieldError>}
            </Field>
          )}
          <Field>
            <FieldLabel>
              <Label>Manufacturer</Label>
            </FieldLabel>
            <FieldContent>
              <Input
                placeholder="e.g. Yageo"
                value={part.manufacturer}
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
                value={part.description}
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
                value={part.footprint_id || 'none'}
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
                value={part.status}
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
                value={part.tag_ids}
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
                value={part.tolerance}
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
                value={part.voltage_rating}
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
                value={part.power_rating}
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
                value={part.target_stock}
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
                value={part.storage_notes}
                onChange={(e) => setPart({ storage_notes: e.target.value })}
              />
            </FieldContent>
          </Field>
          <Field className="col-span-2 @2xl:col-span-4">
            <div className="flex items-center space-x-2">
              <Checkbox
                id={`${mode}_rohs_compliant`}
                checked={part.rohs_compliant}
                onCheckedChange={(checked) => setPart({ rohs_compliant: checked === true })}
              />
              <Label htmlFor={`${mode}_rohs_compliant`} className="cursor-pointer font-normal">
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
            {allSuppliers.length === 0 ? 'No suppliers exist yet.' : 'All suppliers already linked.'}
          </p>
        )}
      </Section>
    </div>
  )
}
