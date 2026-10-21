import { FormEvent } from 'react'
import { useForm } from '@inertiajs/react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

import type { Order, SupplierOption } from './types'
import { t } from '@/lib/i18n'

interface EditOrderDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  order: Order
  suppliers: SupplierOption[]
}

// Edit the order's supplier, reference, dates and notes.
export function EditOrderDialog({ open, onOpenChange, order, suppliers }: EditOrderDialogProps) {
  const editForm = useForm({
    order: {
      supplier_id: String(order.supplier.id),
      reference: order.reference ?? '',
      ordered_at: order.ordered_at ?? '',
      expected_delivery: order.expected_delivery ?? '',
      notes: order.notes ?? '',
    },
  })

  const submitEdit = (e: FormEvent) => {
    e.preventDefault()
    editForm.patch(`/orders/${order.id}`, {
      preserveScroll: true,
      onSuccess: () => onOpenChange(false),
    })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={submitEdit}>
          <DialogHeader>
            <DialogTitle>{t('Edit order')}</DialogTitle>
            <DialogDescription>{t('Update the supplier, reference, dates, and notes.')}</DialogDescription>
          </DialogHeader>

          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="edit-supplier">{t('Supplier')}</Label>
              <Select
                value={editForm.data.order.supplier_id}
                onValueChange={(value) => editForm.setData('order', { ...editForm.data.order, supplier_id: value })}
              >
                <SelectTrigger id="edit-supplier">
                  <SelectValue placeholder={t('Select a supplier')} />
                </SelectTrigger>
                <SelectContent>
                  {suppliers.map((supplier) => (
                    <SelectItem key={supplier.id} value={String(supplier.id)}>
                      {supplier.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label htmlFor="edit-reference">{t('Reference')}</Label>
              <Input
                id="edit-reference"
                value={editForm.data.order.reference}
                onChange={(e) => editForm.setData('order', { ...editForm.data.order, reference: e.target.value })}
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-2">
                <Label htmlFor="edit-ordered">{t('Ordered on')}</Label>
                <Input
                  id="edit-ordered"
                  type="date"
                  value={editForm.data.order.ordered_at}
                  onChange={(e) => editForm.setData('order', { ...editForm.data.order, ordered_at: e.target.value })}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="edit-expected">{t('Expected')}</Label>
                <Input
                  id="edit-expected"
                  type="date"
                  value={editForm.data.order.expected_delivery}
                  onChange={(e) => editForm.setData('order', { ...editForm.data.order, expected_delivery: e.target.value })}
                />
              </div>
            </div>
            <div className="space-y-2">
              <Label htmlFor="edit-notes">{t('Notes')}</Label>
              <Textarea
                id="edit-notes"
                rows={3}
                value={editForm.data.order.notes}
                onChange={(e) => editForm.setData('order', { ...editForm.data.order, notes: e.target.value })}
              />
            </div>
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              {t('Cancel')}
            </Button>
            <Button type="submit" disabled={editForm.processing}>
              {t('Save changes')}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
