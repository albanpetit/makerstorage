import { useForm } from '@inertiajs/react'
import { FormEvent, useEffect, useMemo, useRef, useState } from 'react'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import { Label } from '@/components/ui/label'
import { printOnPrinterWithToast, useLabelTarget } from '@/components/print-labels-dialog'
import { type LabelFormatId, type LabelItem, labelForPart, printLabels } from '@/lib/labels'
import type { Flash } from '@/types'
import { LookupResult } from '@/components/supplier-lookup'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

import { PartFormBody } from '@/components/part-form/part-form-body'
import { usePartSuppliers } from '@/components/part-form/use-part-suppliers'
import {
  AddPartPrefill,
  BagBox,
  BagOption,
  Category,
  EMPTY_PART,
  Footprint,
  lookupResultPatch,
  partPayload,
  StorageLocationOption,
  Supplier,
  Tag,
} from '@/components/part-form/types'
import { t, tx } from '@/lib/i18n'

const PRINT_LABEL_STORAGE_KEY = 'makerstorage.printNewPartLabel'

function storedPrintLabel() {
  try {
    return window.localStorage.getItem(PRINT_LABEL_STORAGE_KEY) === '1'
  } catch {
    return false
  }
}

interface AddPartDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  categories: Category[]
  footprints: Footprint[]
  suppliers: Supplier[]
  tags: Tag[]
  storageLocations: StorageLocationOption[]
  supplierLookupEnabled?: boolean
  // Manual IPN mode: the operator types the reference instead of it being
  // generated on save, so the field is shown and editable.
  ipnManualEntry?: boolean
  // Box & bag numbering: the free bags (null in the other modes).
  bagOptions?: BagOption[] | null
  // ...and the boxes a new bag can be opened in.
  bagBoxes?: BagBox[] | null
  // Opened from a scanned supplier label: what the label says about the part.
  // The dialog then returns to the scanner once the part is created.
  prefill?: AddPartPrefill | null
}

export function AddPartDialog({
  open,
  onOpenChange,
  categories,
  footprints,
  suppliers,
  tags,
  storageLocations,
  supplierLookupEnabled = false,
  ipnManualEntry = false,
  bagOptions = null,
  bagBoxes = null,
  prefill = null,
}: AddPartDialogProps) {
  const [detailsOpen, setDetailsOpen] = useState(false)
  const [printLabel, setPrintLabel] = useState(storedPrintLabel)
  const labelTarget = useLabelTarget(open && printLabel)
  const [suppliersOpen, setSuppliersOpen] = useState(false)
  const suppliersController = usePartSuppliers(suppliers)

  // Datasheet/image URLs from the chosen catalog match, downloaded + attached
  // server-side on create.
  const [attach, setAttach] = useState<{ datasheet_url: string | null; image_url: string | null }>({
    datasheet_url: null,
    image_url: null,
  })

  // A user-picked image file overrides any supplier (hotlinked) image. Preview
  // the local file if present, otherwise the supplier image URL.
  const [imageFile, setImageFile] = useState<File | null>(null)
  const imagePreview = useMemo(
    () => (imageFile ? URL.createObjectURL(imageFile) : attach.image_url),
    [imageFile, attach.image_url],
  )
  useEffect(() => {
    if (!imageFile) return
    return () => URL.revokeObjectURL(imagePreview as string)
  }, [imageFile, imagePreview])

  const form = useForm({
    part: { ...EMPTY_PART },
    initial_location_id: '',
    initial_quantity: '',
  })
  const { data, setData } = form

  // The label prefill only applies to the dialog it opened; closing it (or
  // creating the part) returns to a blank form.
  const [activePrefill, setActivePrefill] = useState(prefill)
  const prefillApplied = useRef(false)
  useEffect(() => {
    if (!open || !activePrefill || prefillApplied.current) return
    prefillApplied.current = true
    setData({
      ...data,
      part: {
        ...data.part,
        name: activePrefill.mpn || data.part.name,
        mpn: activePrefill.mpn || data.part.mpn,
        manufacturer: activePrefill.manufacturer || data.part.manufacturer,
      },
      initial_quantity: activePrefill.quantity || data.initial_quantity,
    })
    if (activePrefill.provider && activePrefill.supplier_sku) {
      suppliersController.applySupplierFromResult(
        { provider: activePrefill.provider, supplier_sku: activePrefill.supplier_sku } as LookupResult,
        () => setSuppliersOpen(true),
      )
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, activePrefill])

  // Fold the pending suppliers and catalog asset URLs into the payload right
  // before it goes over the wire.
  form.transform((payload) => ({
    ...payload,
    datasheet_url: attach.datasheet_url,
    image_url: attach.image_url,
    ...(activePrefill ? { return_to: 'scan' } : {}),
    part: {
      ...partPayload(payload.part),
      ...(imageFile ? { images: [imageFile] } : {}),
      part_suppliers_attributes: suppliersController.suppliersAttributes(),
    },
  }))

  const setPart = (patch: Partial<typeof EMPTY_PART>) => setData('part', { ...data.part, ...patch })

  const resetAll = () => {
    form.reset()
    form.clearErrors()
    suppliersController.reset()
    setDetailsOpen(false)
    setSuppliersOpen(false)
    setAttach({ datasheet_url: null, image_url: null })
    setImageFile(null)
    setActivePrefill(null)
  }

  // Prefill the form from a chosen catalog match.
  const applyResult = (result: LookupResult) => {
    setPart(lookupResultPatch(result, data.part))
    setAttach({ datasheet_url: result.datasheet_url, image_url: result.image_url })
    setDetailsOpen(true)
    suppliersController.applySupplierFromResult(result, () => setSuppliersOpen(true))
  }

  const handleOpenChange = (next: boolean) => {
    if (!next) resetAll()
    onOpenChange(next)
  }

  const choosePrintLabel = (checked: boolean) => {
    setPrintLabel(checked)
    try {
      window.localStorage.setItem(PRINT_LABEL_STORAGE_KEY, checked ? '1' : '0')
    } catch {
      // The choice just isn't kept.
    }
  }

  // A network printer prints straight away; the browser's print dialog needs a
  // click of its own (popup blockers refuse a window opened after the save).
  const printNewPartLabel = (item: LabelItem) => {
    if (labelTarget.printer) {
      printOnPrinterWithToast(labelTarget.printer, Promise.resolve([ item ]))
      return
    }
    const format = labelTarget.target as LabelFormatId
    toast(t('Part created'), {
      description: t('Print the label for {name}?', { name: item.title }),
      action: { label: t('Print label'), onClick: () => printLabels([ item ], format, window.open('', '_blank')) },
    })
  }

  const submit = (e: FormEvent) => {
    e.preventDefault()
    form.post('/parts', {
      preserveScroll: true,
      preserveState: true,
      onSuccess: (page) => {
        const created = (page.props.flash as Flash | undefined)?.created_part
        if (printLabel && created) printNewPartLabel(labelForPart(created))
        resetAll()
        onOpenChange(false)
      },
    })
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="flex max-h-[90svh] flex-col gap-0 p-0 sm:max-w-2xl lg:max-w-4xl">
        <DialogHeader className="border-b px-6 py-4">
          <DialogTitle>{t('Add part')}</DialogTitle>
          <DialogDescription>
            {t('Fill in the essentials — expand the sections below for more detail.')}
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={submit} className="flex min-h-0 flex-1 flex-col">
          <PartFormBody
            mode="add"
            part={data.part}
            setPart={setPart}
            errors={form.errors as unknown as Record<string, string>}
            categories={categories}
            footprints={footprints}
            tags={tags}
            ipnManualEntry={ipnManualEntry}
            bagOptions={bagOptions}
            bagBoxes={bagBoxes}
            supplierLookupEnabled={supplierLookupEnabled}
            autoLookup={activePrefill?.mpn ?? null}
            onApplyLookup={applyResult}
            attach={attach}
            imagePreview={imagePreview}
            imageFile={imageFile}
            onImageFileChange={setImageFile}
            detailsOpen={detailsOpen}
            setDetailsOpen={setDetailsOpen}
            suppliersOpen={suppliersOpen}
            setSuppliersOpen={setSuppliersOpen}
            suppliersController={suppliersController}
            allSuppliers={suppliers}
            storageLocations={storageLocations}
            initialLocationId={data.initial_location_id}
            initialQuantity={data.initial_quantity}
            onInitialLocationChange={(value) => setData('initial_location_id', value)}
            onInitialQuantityChange={(value) => setData('initial_quantity', value)}
          />

          <DialogFooter className="items-center border-t px-6 py-4">
            <div className="mr-auto flex items-center gap-2">
              <Checkbox id="print-new-part-label" checked={printLabel} onCheckedChange={(checked) => choosePrintLabel(checked === true)} />
              <Label htmlFor="print-new-part-label" className="text-sm font-normal">
                {printLabel && labelTarget.printer
                  ? tx('Print its label {printer}', { printer: <span className="text-muted-foreground">{t('on {name}', { name: labelTarget.printer.name })}</span> })
                  : t('Print its label')}
              </Label>
            </div>
            <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>{t('Cancel')}</Button>
            <Button type="submit" disabled={form.processing}>{t('Add part')}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
