import { useState } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import {
  Move, Tag as TagIcon, Trash2, Layers, CircleDot, Tags, Truck, Download,
} from 'lucide-react'

import { usePermissions } from '@/hooks/use-permissions'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { CategorySelect } from '@/components/category-select'
import { StorageLocationSelect } from '@/components/storage-location-select'
import { TagPicker } from '@/components/tag-picker'
import { PrintLabelsDialog } from '@/components/print-labels-dialog'
import { labelCodeForPart, type LabelItem } from '@/lib/labels'
import {
  Dialog,
  DialogContent,
  DialogDescription,
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

import { exportCsv } from './csv'
import { LIFECYCLE_META, locationLabel } from './part-meta'
import type { Category, Part, StorageLocationOption, Supplier, Tag } from './types'
import { t, tn } from '@/lib/i18n'

interface BulkActionsProps {
  selected: number[]
  // Resolves the selected parts, fetching any not on the current page.
  loadSelectedParts: () => Promise<Part[]>
  hiddenSelectedCount: number
  onClearSelection: () => void
  categories: Category[]
  suppliers: Supplier[]
  tags: Tag[]
  storageLocations: StorageLocationOption[]
}

function partLabel(part: Part): LabelItem {
  const title = part.ipn || part.mpn || part.sku || part.name
  return {
    code: labelCodeForPart(part),
    title,
    lines: [
      part.name !== title ? part.name : '',
      part.mpn && part.mpn !== title ? part.mpn : '',
      locationLabel(part.location_names),
    ],
  }
}

// The dark bar shown while parts are selected, plus the edit + confirmation
// dialogs behind each of its bulk actions (PartsController#bulk_*).
export function BulkActions({
  selected, loadSelectedParts, hiddenSelectedCount, onClearSelection,
  categories, suppliers, tags, storageLocations,
}: BulkActionsProps) {
  const { canWrite, canAdminister } = usePermissions()

  const [moveOpen, setMoveOpen] = useState(false)
  const [labelsOpen, setLabelsOpen] = useState(false)
  const [moveLocationId, setMoveLocationId] = useState('')
  const [moveConfirmOpen, setMoveConfirmOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [bulkSubmitting, setBulkSubmitting] = useState(false)

  const [categoryOpen, setCategoryOpen] = useState(false)
  const [categoryValue, setCategoryValue] = useState('')
  const [categoryConfirmOpen, setCategoryConfirmOpen] = useState(false)
  const [statusOpen, setStatusOpen] = useState(false)
  const [statusValue, setStatusValue] = useState<Part['status'] | ''>('')
  const [statusConfirmOpen, setStatusConfirmOpen] = useState(false)
  const [tagsOpen, setTagsOpen] = useState(false)
  const [tagsMode, setTagsMode] = useState<'add' | 'remove'>('add')
  const [tagsValue, setTagsValue] = useState<number[]>([])
  const [tagsConfirmOpen, setTagsConfirmOpen] = useState(false)
  const [supplierOpen, setSupplierOpen] = useState(false)
  const [supplierValue, setSupplierValue] = useState('')
  const [supplierConfirmOpen, setSupplierConfirmOpen] = useState(false)

  const selectedCount = selected.length
  const hiddenNote = hiddenSelectedCount > 0 ? t(' This includes parts hidden by your current filters.') : ''

  const openMove = () => {
    setMoveLocationId('')
    setMoveConfirmOpen(false)
    setMoveOpen(true)
  }

  const openCategory = () => {
    setCategoryValue('')
    setCategoryConfirmOpen(false)
    setCategoryOpen(true)
  }

  const openStatus = () => {
    setStatusValue('')
    setStatusConfirmOpen(false)
    setStatusOpen(true)
  }

  const openTags = () => {
    setTagsMode('add')
    setTagsValue([])
    setTagsConfirmOpen(false)
    setTagsOpen(true)
  }

  const openSupplier = () => {
    setSupplierValue('')
    setSupplierConfirmOpen(false)
    setSupplierOpen(true)
  }

  // Shared visit options. On success, the server has applied the action and
  // Inertia has reloaded the (now updated) part list, so the selection is
  // cleared. On error (a rejected bulk action, e.g. a tampered/invalid id —
  // surfaced via the `errors` Inertia prop rather than a plain redirect, see
  // PartsController#bulk_error), only the confirmation step is closed: the
  // selection and the underlying edit dialog stay put so the user can see the
  // flash alert and retry instead of silently losing their in-progress edit.
  const bulkVisitOptions = (closeDialog: () => void, closeConfirm: () => void = closeDialog) => ({
    preserveScroll: true,
    onStart: () => setBulkSubmitting(true),
    onFinish: () => setBulkSubmitting(false),
    onSuccess: () => {
      closeDialog()
      onClearSelection()
    },
    onError: () => {
      closeConfirm()
    },
  })

  const submitMove = () => {
    if (!moveLocationId) return
    router.post('/parts/bulk_move',
      { part_ids: selected, storage_location_id: moveLocationId },
      bulkVisitOptions(() => { setMoveConfirmOpen(false); setMoveOpen(false) }, () => setMoveConfirmOpen(false)))
  }

  const submitDelete = () => {
    router.delete('/parts/bulk_destroy', {
      data: { part_ids: selected },
      ...bulkVisitOptions(() => setDeleteOpen(false)),
    })
  }

  const submitCategory = () => {
    if (!categoryValue) return
    router.post('/parts/bulk_update_category',
      { part_ids: selected, category_id: categoryValue },
      bulkVisitOptions(() => { setCategoryConfirmOpen(false); setCategoryOpen(false) }, () => setCategoryConfirmOpen(false)))
  }

  const submitStatus = () => {
    if (!statusValue) return
    router.post('/parts/bulk_update_status',
      { part_ids: selected, status: statusValue },
      bulkVisitOptions(() => { setStatusConfirmOpen(false); setStatusOpen(false) }, () => setStatusConfirmOpen(false)))
  }

  const submitTags = () => {
    if (tagsValue.length === 0) return
    router.post('/parts/bulk_update_tags',
      { part_ids: selected, tag_ids: tagsValue, mode: tagsMode },
      bulkVisitOptions(() => { setTagsConfirmOpen(false); setTagsOpen(false) }, () => setTagsConfirmOpen(false)))
  }

  const submitSupplier = () => {
    if (!supplierValue) return
    router.post('/parts/bulk_assign_supplier',
      { part_ids: selected, supplier_id: supplierValue },
      bulkVisitOptions(() => { setSupplierConfirmOpen(false); setSupplierOpen(false) }, () => setSupplierConfirmOpen(false)))
  }

  const exportSelected = () => {
    loadSelectedParts()
      .then(exportCsv)
      .catch(() => toast.error(t('Could not load the selected parts.')))
  }

  const bulkActions = [
    { label: t('Move'), icon: Move, action: openMove },
    { label: t('Category'), icon: Layers, action: openCategory },
    { label: t('Status'), icon: CircleDot, action: openStatus },
    { label: t('Tags'), icon: Tags, action: openTags },
    { label: t('Supplier'), icon: Truck, action: openSupplier },
    { label: t('Labels'), icon: TagIcon, action: () => setLabelsOpen(true) },
    { label: t('Export'), icon: Download, action: exportSelected },
    // Bulk delete is admin-gated server-side (PartsController#bulk_destroy) —
    // hidden here too so members/viewers don't hit a dead-end confirmation
    // dialog for an action the server will always reject.
    ...(canAdminister ? [ { label: t('Delete'), icon: Trash2, action: () => setDeleteOpen(true) } ] : []),
  ]

  return (
    <>
      {/* Bulk action bar */}
      {canWrite && selected.length > 0 && (
        <div className="flex shrink-0 items-center gap-3 bg-foreground px-5 py-2.5 text-background">
          <span className="text-sm font-medium">
            {tn('{count} selected', '{count} selected', selected.length)}
            {hiddenSelectedCount > 0 && (
              <span className="ml-1 font-normal text-background/75">
                {tn('(includes {count} hidden by filters)', '(includes {count} hidden by filters)', hiddenSelectedCount)}
              </span>
            )}
          </span>
          <div className="h-5 w-px bg-background/25" />
          {bulkActions.map((action) => (
            <Button
              key={action.label}
              variant="ghost"
              size="sm"
              onClick={action.action}
              className="h-7 px-2 font-normal hover:bg-background/10 hover:text-background"
            >
              <action.icon className="size-4" />
              {action.label}
            </Button>
          ))}
          <div className="flex-1" />
          <Button
            variant="ghost"
            size="sm"
            onClick={onClearSelection}
            className="h-7 px-2 font-normal text-background/75 hover:bg-background/10 hover:text-background"
          >
            {t('Deselect')}
          </Button>
        </div>
      )}

    <PrintLabelsDialog
      open={labelsOpen}
      onOpenChange={setLabelsOpen}
      count={selectedCount}
      loadItems={() => loadSelectedParts().then((parts) => parts.map(partLabel))}
      title={tn('Print labels for {count} part', 'Print labels for {count} parts', selectedCount)}
    />

    {/* Bulk move modal */}
    <Dialog open={moveOpen} onOpenChange={setMoveOpen}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{tn('Move {count} part', 'Move {count} parts', selectedCount)}</DialogTitle>
          <DialogDescription>
            {tn(
              'All stock for the selected part is relocated into the destination location. Parts with no stock are skipped.',
              'All stock for the selected parts is relocated into the destination location. Parts with no stock are skipped.',
              selectedCount,
            )}
          </DialogDescription>
        </DialogHeader>

        <div className="min-w-0 space-y-2">
          <Label htmlFor="bulk-move-location">{t('Destination location')}</Label>
          <StorageLocationSelect
            id="bulk-move-location"
            locations={storageLocations}
            value={moveLocationId}
            onValueChange={setMoveLocationId}
            placeholder={t('Choose a location')}
            allowCreate
          />
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setMoveOpen(false)}>{t('Cancel')}</Button>
          <Button disabled={!moveLocationId || bulkSubmitting} onClick={() => setMoveConfirmOpen(true)}>
            {tn('Move part', 'Move parts', selectedCount)}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <AlertDialog open={moveConfirmOpen} onOpenChange={setMoveConfirmOpen}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{tn('Move {count} part?', 'Move {count} parts?', selectedCount)}</AlertDialogTitle>
          <AlertDialogDescription>
            {tn(
              "This writes stock-out and stock-in movements for every location currently holding the selected part. This can't be undone.",
              "This writes stock-out and stock-in movements for every location currently holding the selected parts. This can't be undone.",
              selectedCount,
            )}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={bulkSubmitting}>{t('Cancel')}</AlertDialogCancel>
          <AlertDialogAction disabled={bulkSubmitting} onClick={(e) => { e.preventDefault(); submitMove() }}>
            {bulkSubmitting ? t('Moving…') : tn('Move part', 'Move parts', selectedCount)}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>

    {/* Bulk category modal */}
    <Dialog open={categoryOpen} onOpenChange={setCategoryOpen}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{tn('Set category for {count} part', 'Set category for {count} parts', selectedCount)}</DialogTitle>
          <DialogDescription>
            {t('Replaces the category on every selected part.')}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-2">
          <Label htmlFor="bulk-category">{t('Category')}</Label>
          <CategorySelect
            id="bulk-category"
            categories={categories}
            value={categoryValue}
            onValueChange={setCategoryValue}
            placeholder={t('Choose a category')}
            allowCreate={false}
          />
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setCategoryOpen(false)}>{t('Cancel')}</Button>
          <Button disabled={!categoryValue || bulkSubmitting} onClick={() => setCategoryConfirmOpen(true)}>
            {t('Set category')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <AlertDialog open={categoryConfirmOpen} onOpenChange={setCategoryConfirmOpen}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{tn('Set category for {count} part?', 'Set category for {count} parts?', selectedCount)}</AlertDialogTitle>
          <AlertDialogDescription>
            {t('This overwrites the current category on every selected part.')}{hiddenNote}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={bulkSubmitting}>{t('Cancel')}</AlertDialogCancel>
          <AlertDialogAction disabled={bulkSubmitting} onClick={(e) => { e.preventDefault(); submitCategory() }}>
            {bulkSubmitting ? t('Setting…') : t('Set category')}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>

    {/* Bulk status modal */}
    <Dialog open={statusOpen} onOpenChange={setStatusOpen}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{tn('Set status for {count} part', 'Set status for {count} parts', selectedCount)}</DialogTitle>
          <DialogDescription>
            {t('Replaces the lifecycle status on every selected part.')}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-2">
          <Label htmlFor="bulk-status">{t('Status')}</Label>
          <Select value={statusValue} onValueChange={(value) => setStatusValue(value as Part['status'])}>
            <SelectTrigger id="bulk-status">
              <SelectValue placeholder={t('Choose a status')} />
            </SelectTrigger>
            <SelectContent>
              {(Object.keys(LIFECYCLE_META) as Part['status'][]).map((status) => (
                <SelectItem key={status} value={status}>{LIFECYCLE_META[status].label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setStatusOpen(false)}>{t('Cancel')}</Button>
          <Button disabled={!statusValue || bulkSubmitting} onClick={() => setStatusConfirmOpen(true)}>
            {t('Set status')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <AlertDialog open={statusConfirmOpen} onOpenChange={setStatusConfirmOpen}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{tn('Set status for {count} part?', 'Set status for {count} parts?', selectedCount)}</AlertDialogTitle>
          <AlertDialogDescription>
            {t('This overwrites the lifecycle status on every selected part.')}{hiddenNote}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={bulkSubmitting}>{t('Cancel')}</AlertDialogCancel>
          <AlertDialogAction disabled={bulkSubmitting} onClick={(e) => { e.preventDefault(); submitStatus() }}>
            {bulkSubmitting ? t('Setting…') : t('Set status')}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>

    {/* Bulk tags modal */}
    <Dialog open={tagsOpen} onOpenChange={setTagsOpen}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{tn('Edit tags for {count} part', 'Edit tags for {count} parts', selectedCount)}</DialogTitle>
          <DialogDescription>
            {t('Add or remove the chosen tags across every selected part.')}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="inline-flex rounded-md border p-0.5">
            {(['add', 'remove'] as const).map((mode) => (
              <Button
                key={mode}
                type="button"
                variant={tagsMode === mode ? 'default' : 'ghost'}
                size="sm"
                onClick={() => setTagsMode(mode)}
                className="h-7 rounded px-3"
              >
                {mode === 'add' ? t('Add') : t('Remove')}
              </Button>
            ))}
          </div>

          <div className="space-y-2">
            <Label>{t('Tags')}</Label>
            <TagPicker tags={tags} value={tagsValue} onChange={setTagsValue} />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setTagsOpen(false)}>{t('Cancel')}</Button>
          <Button disabled={tagsValue.length === 0 || bulkSubmitting} onClick={() => setTagsConfirmOpen(true)}>
            {tagsMode === 'add' ? t('Add tags') : t('Remove tags')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <AlertDialog open={tagsConfirmOpen} onOpenChange={setTagsConfirmOpen}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>
            {tagsMode === 'add'
              ? tn('Add tags to {count} part?', 'Add tags to {count} parts?', selectedCount)
              : tn('Remove tags from {count} part?', 'Remove tags from {count} parts?', selectedCount)}
          </AlertDialogTitle>
          <AlertDialogDescription>
            {tagsMode === 'add'
              ? t('This adds the chosen tags to every selected part.')
              : t('This removes the chosen tags from every selected part.')}
            {hiddenNote}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={bulkSubmitting}>{t('Cancel')}</AlertDialogCancel>
          <AlertDialogAction disabled={bulkSubmitting} onClick={(e) => { e.preventDefault(); submitTags() }}>
            {bulkSubmitting ? t('Saving…') : tagsMode === 'add' ? t('Add tags') : t('Remove tags')}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>

    {/* Bulk supplier modal */}
    <Dialog open={supplierOpen} onOpenChange={setSupplierOpen}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{tn('Assign supplier for {count} part', 'Assign supplier for {count} parts', selectedCount)}</DialogTitle>
          <DialogDescription>
            {t('Links the supplier to every selected part and marks it preferred.')}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-2">
          <Label htmlFor="bulk-supplier">{t('Supplier')}</Label>
          <Select value={supplierValue} onValueChange={setSupplierValue}>
            <SelectTrigger id="bulk-supplier">
              <SelectValue placeholder={t('Choose a supplier')} />
            </SelectTrigger>
            <SelectContent>
              {suppliers.map((supplier) => (
                <SelectItem key={supplier.id} value={String(supplier.id)}>{supplier.name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          {suppliers.length === 0 && (
            <p className="text-sm text-muted-foreground">{t('No suppliers yet — add one first.')}</p>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setSupplierOpen(false)}>{t('Cancel')}</Button>
          <Button disabled={!supplierValue || bulkSubmitting} onClick={() => setSupplierConfirmOpen(true)}>
            {t('Assign supplier')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <AlertDialog open={supplierConfirmOpen} onOpenChange={setSupplierConfirmOpen}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{tn('Assign supplier for {count} part?', 'Assign supplier for {count} parts?', selectedCount)}</AlertDialogTitle>
          <AlertDialogDescription>
            {t("This links the chosen supplier to every selected part and marks it preferred, which also updates each part's unit price to match.")}
            {hiddenNote}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={bulkSubmitting}>{t('Cancel')}</AlertDialogCancel>
          <AlertDialogAction disabled={bulkSubmitting} onClick={(e) => { e.preventDefault(); submitSupplier() }}>
            {bulkSubmitting ? t('Assigning…') : t('Assign supplier')}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>

    {/* Bulk delete confirmation */}
    <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{tn('Delete {count} part?', 'Delete {count} parts?', selectedCount)}</AlertDialogTitle>
          <AlertDialogDescription>
            {tn(
              "This permanently removes the selected part along with its stock and movement history. This can't be undone.",
              "This permanently removes the selected parts along with their stock and movement history. This can't be undone.",
              selectedCount,
            )}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={bulkSubmitting}>{t('Cancel')}</AlertDialogCancel>
          <AlertDialogAction
            disabled={bulkSubmitting}
            onClick={(e) => { e.preventDefault(); submitDelete() }}
            className="bg-destructive text-white hover:bg-destructive/90"
          >
            {bulkSubmitting ? t('Deleting…') : tn('Delete part', 'Delete parts', selectedCount)}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
    </>
  )
}
