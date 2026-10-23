import { Fragment, ReactNode, useEffect, useState } from 'react'
import { ChevronRight, CircleAlert, ImagePlus, Layers, Plus, Trash2, Star, X } from 'lucide-react'

import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Checkbox } from '@/components/ui/checkbox'
import { Badge } from '@/components/ui/badge'
import { CategorySelect } from '@/components/category-select'
import { StorageLocationSelect } from '@/components/storage-location-select'
import { TagPicker } from '@/components/tag-picker'
import { SupplierLookup, LookupResult } from '@/components/supplier-lookup'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectSeparator,
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

import { useParameterDefinitions } from '@/components/parameters/use-parameter-definitions'
import { PartParametersSection } from './part-parameters-section'
import { PartSuppliersController } from './use-part-suppliers'
import { PriceBreaksEditor } from './price-breaks-editor'
import { formatUnitPrice } from '@/lib/money'
import {
  BagBox,
  BagOption,
  Category,
  fieldLabel,
  Footprint,
  PartFormData,
  StorageLocationOption,
  Tag,
} from './types'
import { t, tn } from '@/lib/i18n'
import { mountingTypeLabel } from '@/lib/mounting-types'

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
      <Button
        type="button"
        variant="ghost"
        onClick={onToggle}
        className="flex h-auto w-full justify-start gap-2 px-4 py-3 text-left font-normal whitespace-normal has-[>svg]:px-4 hover:bg-transparent dark:hover:bg-transparent"
      >
        <ChevronRight className={`size-4 shrink-0 text-muted-foreground transition-transform ${open ? 'rotate-90' : ''}`} />
        <span className="flex-1">
          <span className="block text-sm font-medium">{title}</span>
          <span className="block text-xs text-muted-foreground">{description}</span>
        </span>
      </Button>
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
  // Box & bag numbering: the bags to choose from (null in the other modes).
  bagOptions?: BagOption[] | null
  // ...and the boxes a new bag can be opened in, for when no free bag suits.
  bagBoxes?: BagBox[] | null

  // Supplier catalog lookup
  supplierLookupEnabled: boolean
  // A part number to look up as soon as the form shows (from a scanned label).
  autoLookup?: string | null
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
  bagOptions = null,
  bagBoxes = null,
  supplierLookupEnabled,
  autoLookup = null,
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
    setPriceBreaks,
  } = suppliersController
  // The supplier row whose price breaks are open for editing.
  const [breaksOpenFor, setBreaksOpenFor] = useState<string | null>(null)

  // Tolerance / Voltage / Power fields mirror the parameters of those names
  // (Part#sync_parameter_fields): when the organization has them, the
  // parameter rows replace the fields.
  const { definitions } = useParameterDefinitions()
  const parameterNames = new Set(definitions.map((d) => d.name.toLowerCase()))
  const showField = (name: string) => !parameterNames.has(name)

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
      ? t('Your uploaded image will be used.')
      : t('Your uploaded image will replace the current one.')
    : attach.image_url
      ? t('Using the supplier image — upload a file to override it.')
      : mode === 'add'
        ? t('Optional. PNG or JPG.')
        : t('Upload a file to replace the current image.')

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
          autoQuery={autoLookup}
          onApply={onApplyLookup}
          attached={{ datasheet: !!attach.datasheet_url, image: !!attach.image_url }}
        />
      )}

      {/* Essentials */}
      <div className="grid grid-cols-2 gap-4 @2xl:grid-cols-4">
        <Field className="col-span-2 @2xl:col-span-4">
          <FieldLabel>
            <Label>{t('Name *')}</Label>
          </FieldLabel>
          <FieldContent>
            <Input
              placeholder={t('e.g. Resistor 10k 1% 0603')}
              value={part.name}
              onChange={(e) => setPart({ name: e.target.value })}
              autoFocus
            />
          </FieldContent>
          {errors['part.name'] && <FieldError>{errors['part.name']}</FieldError>}
        </Field>
        <Field className="col-span-2 @2xl:col-span-4">
          <FieldLabel>
            <Label htmlFor="part-category">{t('Category *')}</Label>
          </FieldLabel>
          <FieldContent>
            <CategorySelect
              id="part-category"
              categories={categories}
              value={part.category_id}
              onValueChange={(value) => setPart({ category_id: value })}
            />
          </FieldContent>
          {errors['part.category_id'] && <FieldError>{errors['part.category_id']}</FieldError>}
        </Field>
        <Field className="col-span-2 @2xl:col-span-4">
          <FieldLabel>
            <Label>{t('Image')}</Label>
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
                  aria-label={t('Remove image')}
                >
                  <X className="size-4" />
                </Button>
              )}
            </div>
          </FieldContent>
        </Field>
        <Field>
          <FieldLabel>
            <Label>{t('Value')}</Label>
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
            <Label>{t('Package')}</Label>
          </FieldLabel>
          <FieldContent>
            <Input
              placeholder="e.g. 0603"
              value={part.package_type}
              onChange={(e) => setPart({ package_type: e.target.value })}
            />
          </FieldContent>
        </Field>
        {/* Box & bag numbering: the IPN is the code of the bag the part
            sits in, so the operator picks the bag instead. */}
        {bagOptions && (
          <Field>
            <FieldLabel>
              <Label>{t('Bag')}</Label>
            </FieldLabel>
            <FieldContent>
              <Select
                value={part.new_bag_box_id ? `new:${part.new_bag_box_id}` : part.bag_id || 'none'}
                onValueChange={(value) =>
                  value.startsWith('new:')
                    ? setPart({ bag_id: '', new_bag_box_id: value.slice(4) })
                    : setPart({ bag_id: value === 'none' ? '' : value, new_bag_box_id: '' })
                }
              >
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">
                    {mode === 'add'
                      ? bagOptions.length > 0 ? t('First free bag ({code})', { code: bagOptions[0].code }) : t('No free bag')
                      : t('No bag')}
                  </SelectItem>
                  {bagOptions.map((bag) => (
                    <SelectItem key={bag.id} value={bag.id.toString()}>{bag.code}</SelectItem>
                  ))}
                  {bagBoxes && bagBoxes.length > 0 && (
                    <>
                      <SelectSeparator />
                      <SelectGroup>
                        <SelectLabel>{t('New bag')}</SelectLabel>
                        {bagBoxes.map((box) => (
                          <SelectItem key={`new:${box.id}`} value={`new:${box.id}`}>
                            {box.next_code} <span className="text-muted-foreground">{t('in {name}', { name: box.name })}</span>
                          </SelectItem>
                        ))}
                      </SelectGroup>
                    </>
                  )}
                </SelectContent>
              </Select>
            </FieldContent>
            <p className="text-xs text-muted-foreground">
              {part.new_bag_box_id
                ? t('This bag is added to its box when the part is saved; its code becomes this part’s IPN.')
                : mode === 'add'
                  ? bagOptions.length > 0
                    ? t('The bag’s code becomes this part’s IPN.')
                    : bagBoxes && bagBoxes.length > 0
                      ? t('Every bag is taken: pick a new bag in a box, or the part is saved without an IPN.')
                      : t('Every bag is taken: add bags to a box in Storage zones, or the part is saved without an IPN.')
                  : t('The bag’s code is this part’s IPN. Moving to another bag takes the stock along.')}
            </p>
            {errors['part.bag'] && <FieldError>{errors['part.bag']}</FieldError>}
          </Field>
        )}
        {mode === 'add' && storageLocations && (
          <>
            <Field>
              <FieldLabel>
                <Label>{t('Initial location')}</Label>
              </FieldLabel>
              <FieldContent>
                <StorageLocationSelect
                  id="part-initial-location"
                  locations={storageLocations}
                  value={initialLocationId ?? ''}
                  onValueChange={(value) => onInitialLocationChange?.(value)}
                  noneLabel={bagOptions ? t('In its bag') : t('No location')}
                  allowCreate
                />
              </FieldContent>
            </Field>
            <Field>
              <FieldLabel>
                <Label>{t('Quantity')}</Label>
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
              {errors['initial_quantity'] && <FieldError>{errors['initial_quantity']}</FieldError>}
            </Field>
          </>
        )}
        <Field>
          <FieldLabel>
            <Label>{t('Min. threshold')}</Label>
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
            <Label>{t('Unit price')}</Label>
          </FieldLabel>
          <FieldContent>
            <Input
              placeholder="0.00"
              value={part.unit_price}
              onChange={(e) => setPart({ unit_price: e.target.value })}
            />
          </FieldContent>
          <p className="text-xs text-muted-foreground">{t('Auto-set from your preferred supplier\'s price on save.')}</p>
          {errors['part.unit_price'] && <FieldError>{errors['part.unit_price']}</FieldError>}
        </Field>
      </div>

      {/* Parameters */}
      <PartParametersSection
        categoryId={part.category_id}
        values={part.parameters}
        onChange={(parameters) => setPart({ parameters })}
        error={errors['part.parameters']}
      />

      {/* More details */}
      <Section
        title={t('More details')}
        description={t('Identifiers, classification, specifications')}
        open={detailsOpen}
        onToggle={() => setDetailsOpen((v) => !v)}
      >
        <div className="grid grid-cols-2 gap-4 @2xl:grid-cols-4">
          <Field>
            <FieldLabel>
              <Label>{t('MPN')}</Label>
            </FieldLabel>
            <FieldContent>
              <Input
                placeholder={t('e.g. RC0805FR-0710KL')}
                value={part.mpn}
                onChange={(e) => setPart({ mpn: e.target.value })}
              />
            </FieldContent>
            {errors['part.mpn'] && <FieldError>{errors['part.mpn']}</FieldError>}
          </Field>
          <Field>
            <FieldLabel>
              <Label>{t('Internal SKU')}</Label>
            </FieldLabel>
            <FieldContent>
              <Input
                placeholder={t('e.g. RES-10K-0805')}
                value={part.sku}
                onChange={(e) => setPart({ sku: e.target.value })}
              />
            </FieldContent>
            {errors['part.sku'] && <FieldError>{errors['part.sku']}</FieldError>}
          </Field>
          <Field>
            <FieldLabel>
              <Label>{t('Barcode')}</Label>
            </FieldLabel>
            <FieldContent>
              <Input
                placeholder={t('Scan or enter barcode')}
                value={part.barcode}
                onChange={(e) => setPart({ barcode: e.target.value })}
              />
            </FieldContent>
            {errors['part.barcode'] && <FieldError>{errors['part.barcode']}</FieldError>}
          </Field>
          {/* IPN: in add mode it only appears when the org uses manual numbering
              (auto modes stamp it on save); in edit mode it's always shown but
              read-only unless manual. */}
          {!bagOptions && (mode === 'edit' || ipnManualEntry) && (
            <Field>
              <FieldLabel>
                <Label>{t('Internal part number (IPN)')}</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  placeholder={ipnManualEntry ? t('e.g. MS-00042') : t('Assigned automatically')}
                  value={part.ipn}
                  onChange={(e) => setPart({ ipn: e.target.value })}
                  disabled={mode === 'edit' && !ipnManualEntry}
                />
              </FieldContent>
              <p className="text-xs text-muted-foreground">
                {ipnManualEntry
                  ? mode === 'add'
                    ? t('Manual numbering is on — type this part\'s reference.')
                    : t('Manual numbering is on — edit this part’s reference.')
                  : t('Generated from your numbering settings.')}
              </p>
              {errors['part.ipn'] && <FieldError>{errors['part.ipn']}</FieldError>}
            </Field>
          )}
          <Field>
            <FieldLabel>
              <Label>{t('Manufacturer')}</Label>
            </FieldLabel>
            <FieldContent>
              <Input
                placeholder={t('e.g. Yageo')}
                value={part.manufacturer}
                onChange={(e) => setPart({ manufacturer: e.target.value })}
              />
            </FieldContent>
          </Field>
          <Field className="col-span-2 @2xl:col-span-4">
            <FieldLabel>
              <Label>{t('Description')}</Label>
            </FieldLabel>
            <FieldContent>
              <Textarea
                rows={2}
                placeholder={t('Detailed description of the part')}
                value={part.description}
                onChange={(e) => setPart({ description: e.target.value })}
              />
            </FieldContent>
          </Field>
          <Field>
            <FieldLabel>
              <Label>{t('Footprint')}</Label>
            </FieldLabel>
            <FieldContent>
              <Select
                value={part.footprint_id || 'none'}
                onValueChange={(value) => setPart({ footprint_id: value === 'none' ? '' : value })}
              >
                <SelectTrigger className="w-full">
                  <SelectValue placeholder={t('Select a footprint')} />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">{t('None')}</SelectItem>
                  {footprints.map((footprint) => (
                    <SelectItem key={footprint.id} value={footprint.id.toString()}>
                      {footprint.name}
                      {footprint.mounting_type && ` (${mountingTypeLabel(footprint.mounting_type)})`}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </FieldContent>
          </Field>
          <Field>
            <FieldLabel>
              <Label>{t('Status')}</Label>
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
                  <SelectItem value="active">{t('Active')}</SelectItem>
                  <SelectItem value="discontinued">{t('Discontinued')}</SelectItem>
                  <SelectItem value="obsolete">{t('Obsolete')}</SelectItem>
                </SelectContent>
              </Select>
            </FieldContent>
          </Field>
          <Field className="col-span-2 @2xl:col-span-4">
            <FieldLabel>
              <Label>{t('Tags')}</Label>
            </FieldLabel>
            <FieldContent>
              <TagPicker
                tags={tags}
                value={part.tag_ids}
                onChange={(ids) => setPart({ tag_ids: ids })}
              />
            </FieldContent>
          </Field>
          {showField('tolerance') && (
            <Field>
              <FieldLabel>
                <Label>{t('Tolerance')}</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  placeholder="e.g. 1%, 5%"
                  value={part.tolerance}
                  onChange={(e) => setPart({ tolerance: e.target.value })}
                />
              </FieldContent>
            </Field>
          )}
          {showField('voltage rating') && (
            <Field>
              <FieldLabel>
                <Label>{t('Voltage rating')}</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  placeholder="e.g. 50V"
                  value={part.voltage_rating}
                  onChange={(e) => setPart({ voltage_rating: e.target.value })}
                />
              </FieldContent>
            </Field>
          )}
          {showField('power rating') && (
            <Field>
              <FieldLabel>
                <Label>{t('Power rating')}</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  placeholder="e.g. 0.125W"
                  value={part.power_rating}
                  onChange={(e) => setPart({ power_rating: e.target.value })}
                />
              </FieldContent>
            </Field>
          )}
          <Field>
            <FieldLabel>
              <Label>{t('Target stock')}</Label>
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
              <Label>{t('Storage notes')}</Label>
            </FieldLabel>
            <FieldContent>
              <Textarea
                rows={2}
                placeholder={t('Special storage or handling instructions')}
                value={part.storage_notes}
                onChange={(e) => setPart({ storage_notes: e.target.value })}
              />
            </FieldContent>
          </Field>
          <Field className="col-span-2">
            <FieldLabel>
              <Label>{t('KiCad symbol')}</Label>
            </FieldLabel>
            <FieldContent>
              <Input
                className="font-mono"
                placeholder={t('From the category')}
                value={part.kicad_symbol}
                onChange={(e) => setPart({ kicad_symbol: e.target.value })}
              />
            </FieldContent>
          </Field>
          <Field className="col-span-2">
            <FieldLabel>
              <Label>{t('KiCad footprint')}</Label>
            </FieldLabel>
            <FieldContent>
              <Input
                className="font-mono"
                placeholder={t('From the footprint')}
                value={part.kicad_footprint}
                onChange={(e) => setPart({ kicad_footprint: e.target.value })}
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
                {t('RoHS compliant')}
              </Label>
            </div>
          </Field>
        </div>
      </Section>

      {/* Suppliers */}
      <Section
        title={t('Suppliers')}
        description={pendingSuppliers.length > 0 ? tn('{count} linked', '{count} linked', pendingSuppliers.length) : t('Link suppliers (optional)')}
        open={suppliersOpen}
        onToggle={() => setSuppliersOpen((v) => !v)}
      >
        {pendingSuppliers.length > 0 && (
          <div className="mb-4 overflow-hidden rounded-md border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t('Supplier')}</TableHead>
                  <TableHead>{t('SKU')}</TableHead>
                  <TableHead className="text-right">{t('Price')}</TableHead>
                  <TableHead>{t('Status')}</TableHead>
                  <TableHead className="w-[120px]" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {pendingSuppliers.map((ps) => (
                  <Fragment key={ps.tempId}>
                    <TableRow>
                      <TableCell className="font-medium">{ps.supplier_name}</TableCell>
                      <TableCell>{ps.supplier_sku || '-'}</TableCell>
                      <TableCell className="text-right font-mono">
                        {ps.unit_price ? formatUnitPrice(parseFloat(ps.unit_price)) : '-'}
                        {ps.price_breaks.length > 0 && (
                          <div className="font-sans text-xs font-normal text-muted-foreground">
                            {tn('{count} price break', '{count} price breaks', ps.price_breaks.length)}
                          </div>
                        )}
                      </TableCell>
                      <TableCell>
                        {ps.is_preferred && (
                          <Badge variant="default">
                            <Star className="mr-1 size-3" />
                            {t('Preferred')}
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center gap-1">
                          <Button
                            type="button"
                            variant={breaksOpenFor === ps.tempId ? 'secondary' : 'ghost'}
                            size="icon"
                            onClick={() => setBreaksOpenFor((open) => (open === ps.tempId ? null : ps.tempId))}
                            title={
                              ps.price_breaks.length > 0
                                ? tn('{count} price break', '{count} price breaks', ps.price_breaks.length)
                                : t('Price breaks')
                            }
                          >
                            <Layers className="size-4" />
                          </Button>
                          {!ps.is_preferred && (
                            <Button type="button" variant="ghost" size="icon" onClick={() => setPreferred(ps.tempId)} title={t('Set as preferred')}>
                              <Star className="size-4" />
                            </Button>
                          )}
                          <Button type="button" variant="ghost" size="icon" onClick={() => removePendingSupplier(ps)} title={t('Remove supplier')}>
                            <Trash2 className="size-4 text-destructive" />
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                    {breaksOpenFor === ps.tempId && (
                      <TableRow className="hover:bg-transparent">
                        <TableCell colSpan={5} className="bg-muted/30">
                          <p className="mb-2 text-xs text-muted-foreground">
                            {t('Price per unit from each quantity. Orders use the break for the quantity ordered.')}
                          </p>
                          <PriceBreaksEditor value={ps.price_breaks} onChange={(rows) => setPriceBreaks(ps.tempId, rows)} />
                        </TableCell>
                      </TableRow>
                    )}
                  </Fragment>
                ))}
              </TableBody>
            </Table>
          </div>
        )}

        {availableSuppliers.length > 0 ? (
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2 grid grid-cols-2 gap-3 sm:grid-cols-4">
              <div className="col-span-2 space-y-1.5">
                <Label className="text-xs">{t('Supplier')}</Label>
                <Select
                  value={newSupplier.supplier_id}
                  onValueChange={(value) => setNewSupplier({ ...newSupplier, supplier_id: value })}
                >
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder={t('Select supplier')} />
                  </SelectTrigger>
                  <SelectContent>
                    {availableSuppliers.map((supplier) => (
                      <SelectItem key={supplier.id} value={supplier.id.toString()}>{supplier.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1.5">
                <Label className="text-xs">{t('SKU')}</Label>
                <Input
                  value={newSupplier.supplier_sku}
                  onChange={(e) => setNewSupplier({ ...newSupplier, supplier_sku: e.target.value })}
                />
              </div>
              <div className="space-y-1.5">
                <Label className="text-xs">{t('Price')}</Label>
                <Input
                  type="number"
                  step="0.0001"
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
                {t('Preferred supplier')}
              </label>
              <Button type="button" size="sm" variant="outline" onClick={addPendingSupplier} disabled={!newSupplier.supplier_id}>
                <Plus className="size-4" />
                {t('Add supplier')}
              </Button>
            </div>
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">
            {allSuppliers.length === 0 ? t('No suppliers exist yet.') : t('All suppliers already linked.')}
          </p>
        )}
      </Section>
    </div>
  )
}
