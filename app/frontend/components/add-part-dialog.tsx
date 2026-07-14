import { useForm } from '@inertiajs/react'
import { FormEvent, useEffect, useMemo, useState } from 'react'

import { Button } from '@/components/ui/button'
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
  Category,
  EMPTY_PART,
  Footprint,
  lookupResultPatch,
  StorageLocationOption,
  Supplier,
  Tag,
} from '@/components/part-form/types'

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
}: AddPartDialogProps) {
  const [detailsOpen, setDetailsOpen] = useState(false)
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

  // Fold the pending suppliers and catalog asset URLs into the payload right
  // before it goes over the wire.
  form.transform((payload) => ({
    ...payload,
    datasheet_url: attach.datasheet_url,
    image_url: attach.image_url,
    part: {
      ...payload.part,
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

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="flex max-h-[90svh] flex-col gap-0 p-0 sm:max-w-2xl lg:max-w-4xl">
        <DialogHeader className="border-b px-6 py-4">
          <DialogTitle>Add part</DialogTitle>
          <DialogDescription>
            Fill in the essentials — expand the sections below for more detail.
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
            supplierLookupEnabled={supplierLookupEnabled}
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

          <DialogFooter className="border-t px-6 py-4">
            <Button type="button" variant="outline" onClick={() => handleOpenChange(false)}>Cancel</Button>
            <Button type="submit" disabled={form.processing}>Add part</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
