import { useState } from 'react'
import { router } from '@inertiajs/react'

import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { StorageLocationSelect, type StorageLocationOption } from '@/components/storage-location-select'

import type { Order } from './types'
import { t } from '@/lib/i18n'

interface BulkZoneDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  order: Order
  storageLocations: StorageLocationOption[]
}

// Send every line's full quantity to one zone (OrdersController#assign_storage).
// Remount (via `key`) to start with no zone picked.
export function BulkZoneDialog({ open, onOpenChange, order, storageLocations }: BulkZoneDialogProps) {
  const [bulkZone, setBulkZone] = useState<number | null>(null)

  const submitBulkZone = () => {
    if (bulkZone == null) return
    router.post(
      `/orders/${order.id}/assign_storage`,
      { storage_location_id: bulkZone },
      {
        preserveScroll: true,
        onSuccess: () => {
          onOpenChange(false)
          setBulkZone(null)
        },
      }
    )
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{t('Set storage zone for all lines')}</DialogTitle>
          <DialogDescription>
            {t('Sends every line\'s full quantity to the chosen zone. You can then override individual lines to split them.')}
          </DialogDescription>
        </DialogHeader>
        <div className="py-4">
          <StorageLocationSelect
            locations={storageLocations}
            value={bulkZone != null ? String(bulkZone) : ''}
            onValueChange={(value) => setBulkZone(value ? Number(value) : null)}
            placeholder={t('Select a zone')}
            allowCreate
          />
        </div>
        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            {t('Cancel')}
          </Button>
          <Button type="button" disabled={bulkZone == null} onClick={submitBulkZone}>
            {t('Apply to all lines')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
