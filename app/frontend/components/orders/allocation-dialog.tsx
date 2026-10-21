import { useState } from 'react'
import { router } from '@inertiajs/react'
import { Plus, X } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { StorageLocationSelect, type StorageLocationOption } from '@/components/storage-location-select'

import type { Order, OrderLine } from './types'
import { t, tn } from '@/lib/i18n'

interface AllocationDialogProps {
  order: Order
  allocLine: OrderLine | null
  onClose: () => void
  storageLocations: StorageLocationOption[]
}

function initialRows(line: OrderLine | null) {
  if (!line) return []
  return line.allocations.length > 0
    ? line.allocations.map((a) => ({ storage_location_id: a.storage_location_id as number | null, quantity: String(a.quantity) }))
    : [{ storage_location_id: null, quantity: String(line.quantity) }]
}

// Split one line's received quantity across storage zones. Remount (via
// `key`) when opening it for a line so the rows start from its saved split.
export function AllocationDialog({ order, allocLine, onClose, storageLocations }: AllocationDialogProps) {
  const [allocRows, setAllocRows] = useState<{ storage_location_id: number | null; quantity: string }[]>(() => initialRows(allocLine))

  const patchAllocations = (line: OrderLine, allocations: { storage_location_id: number; quantity: number }[]) => {
    router.patch(
      `/orders/${order.id}/order_lines/${line.id}`,
      { order_line: { allocations } },
      { preserveScroll: true, onSuccess: onClose }
    )
  }

  return (
    <Dialog open={allocLine !== null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-lg">
        {allocLine && (() => {
          const total = allocRows.reduce((sum, r) => sum + (Number(r.quantity) || 0), 0)
          const remaining = allocLine.quantity - total
          const complete = allocRows.length > 0 &&
            allocRows.every((r) => r.storage_location_id != null && Number(r.quantity) > 0) &&
            remaining === 0
          return (
            <>
              <DialogHeader>
                <DialogTitle>{t('Storage for {reference}', { reference: allocLine.part.reference })}</DialogTitle>
                <DialogDescription>
                  {tn(
                    'Split the {count} received unit across one or more zones. They must add up to {count}.',
                    'Split the {count} received units across one or more zones. They must add up to {count}.',
                    allocLine.quantity,
                  )}
                </DialogDescription>
              </DialogHeader>

              <div className="space-y-2 py-4">
                {allocRows.map((row, i) => (
                  <div key={i} className="flex items-center gap-2">
                    <StorageLocationSelect
                      locations={storageLocations}
                      value={row.storage_location_id != null ? String(row.storage_location_id) : ''}
                      onValueChange={(value) => setAllocRows((rows) => rows.map((r, idx) => (idx === i ? { ...r, storage_location_id: value ? Number(value) : null } : r)))}
                      placeholder={t('Select a zone')}
                      className="min-w-0 flex-1"
                      allowCreate
                    />
                    <Input
                      type="number"
                      min={1}
                      value={row.quantity}
                      onChange={(e) => setAllocRows((rows) => rows.map((r, idx) => (idx === i ? { ...r, quantity: e.target.value } : r)))}
                      className="h-9 w-20 text-right font-mono"
                    />
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon-sm"
                      aria-label={t('Remove zone')}
                      disabled={allocRows.length === 1}
                      onClick={() => setAllocRows((rows) => rows.filter((_, idx) => idx !== i))}
                    >
                      <X className="size-4 text-muted-foreground" />
                    </Button>
                  </div>
                ))}

                <div className="flex items-center justify-between pt-1">
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={() => setAllocRows((rows) => [...rows, { storage_location_id: null, quantity: '' }])}
                  >
                    <Plus className="size-4" />
                    {t('Add zone')}
                  </Button>
                  <span className={`text-xs ${remaining === 0 ? 'text-muted-foreground' : 'text-amber-600 dark:text-amber-400'}`}>
                    {remaining === 0 ? t('All units allocated') : remaining > 0 ? t('{count} left to allocate', { count: remaining }) : t('{count} over', { count: -remaining })}
                  </span>
                </div>
              </div>

              <DialogFooter className="sm:justify-between">
                <Button
                  type="button"
                  variant="ghost"
                  onClick={() => patchAllocations(allocLine, [])}
                >
                  {t('Clear (use default location)')}
                </Button>
                <div className="flex gap-2">
                  <Button type="button" variant="outline" onClick={onClose}>
                    {t('Cancel')}
                  </Button>
                  <Button
                    type="button"
                    disabled={!complete}
                    onClick={() =>
                      patchAllocations(
                        allocLine,
                        allocRows.map((r) => ({ storage_location_id: r.storage_location_id as number, quantity: Number(r.quantity) }))
                      )
                    }
                  >
                    {t('Save split')}
                  </Button>
                </div>
              </DialogFooter>
            </>
          )
        })()}
      </DialogContent>
    </Dialog>
  )
}
