import { useForm } from '@inertiajs/react'
import { FormEvent, useEffect, useMemo, useState } from 'react'
import { CircleAlert, Loader2 } from 'lucide-react'

import { Alert, AlertDescription } from '@/components/ui/alert'
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
  FullPart,
  lookupResultPatch,
  Supplier,
  Tag,
  toFormPart,
} from '@/components/part-form/types'

interface EditPartDialogProps {
  partId: number | null
  open: boolean
  onOpenChange: (open: boolean) => void
  categories: Category[]
  footprints: Footprint[]
  suppliers: Supplier[]
  tags: Tag[]
  supplierLookupEnabled?: boolean
  // Manual IPN mode: the operator edits the reference directly. In the other
  // (auto) modes the IPN is generated server-side, so it's shown read-only.
  ipnManualEntry?: boolean
}

export function EditPartDialog({
  partId,
  open,
  onOpenChange,
  categories,
  footprints,
  suppliers,
  tags,
  supplierLookupEnabled = false,
  ipnManualEntry = false,
}: EditPartDialogProps) {
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState('')
  const [detailsOpen, setDetailsOpen] = useState(false)
  const [suppliersOpen, setSuppliersOpen] = useState(false)
  const suppliersController = usePartSuppliers(suppliers)

  // Datasheet/image URLs from a chosen catalog match, downloaded + attached
  // server-side on save.
  const [attach, setAttach] = useState<{ datasheet_url: string | null; image_url: string | null }>({
    datasheet_url: null,
    image_url: null,
  })

  // Manual image upload. A picked file overrides any supplier image; otherwise
  // the preview shows a freshly looked-up supplier image, then the part's
  // current image.
  const [imageFile, setImageFile] = useState<File | null>(null)
  const [currentImageUrl, setCurrentImageUrl] = useState<string | null>(null)
  const imagePreview = useMemo(
    () => (imageFile ? URL.createObjectURL(imageFile) : attach.image_url || currentImageUrl),
    [imageFile, attach.image_url, currentImageUrl],
  )
  useEffect(() => {
    if (!imageFile) return
    return () => URL.revokeObjectURL(imagePreview as string)
  }, [imageFile, imagePreview])

  const form = useForm({ part: { ...EMPTY_PART } })
  const { data, setData } = form

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
        setCurrentImageUrl(part.thumbnail_url)
        suppliersController.seedFromPartSuppliers(part.part_suppliers)
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
      ...(imageFile ? { images: [imageFile] } : {}),
      part_suppliers_attributes: suppliersController.suppliersAttributes(),
    },
  }))

  const setPart = (patch: Partial<typeof EMPTY_PART>) => setData('part', { ...data.part, ...patch })

  const resetLocal = () => {
    form.clearErrors()
    suppliersController.reset()
    setDetailsOpen(false)
    setSuppliersOpen(false)
    setAttach({ datasheet_url: null, image_url: null })
    setImageFile(null)
    setCurrentImageUrl(null)
    setLoadError('')
  }

  // Prefill the form from a chosen catalog match.
  const applyResult = (result: LookupResult) => {
    setPart(lookupResultPatch(result, data.part))
    setAttach({ datasheet_url: result.datasheet_url, image_url: result.image_url })
    setDetailsOpen(true)
    suppliersController.applySupplierFromResult(result, () => setSuppliersOpen(true))
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
            <PartFormBody
              mode="edit"
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
            />

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
