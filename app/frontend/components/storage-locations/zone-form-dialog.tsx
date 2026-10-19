import { FormEvent } from 'react'
import type { InertiaFormProps } from '@inertiajs/react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'
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
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { StorageLocationSelect, type StorageLocationOption } from '@/components/storage-location-select'

import { LOCATION_TYPES, typeMeta } from './zone-meta'
import type { ZoneFormData } from './types'

interface ZoneFormDialogProps {
  mode: 'new' | 'edit'
  open: boolean
  onOpenChange: (open: boolean) => void
  form: InertiaFormProps<ZoneFormData>
  onSubmit: (e: FormEvent) => void
  zones: StorageLocationOption[]
  // Zones that can't be the parent (in edit mode, the zone's own subtree).
  excludeIds?: number[]
}

// Create or edit a storage zone (name, type, parent, code). In edit mode the
// parent picker doubles as "move", and excludes the zone's own subtree.
export function ZoneFormDialog({ mode, open, onOpenChange, form, onSubmit, zones, excludeIds }: ZoneFormDialogProps) {
  const isNew = mode === 'new'
  const data = form.data.storage_location
  const set = (patch: Partial<ZoneFormData['storage_location']>) =>
    form.setData('storage_location', { ...data, ...patch })

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{isNew ? 'New storage zone' : 'Edit zone'}</DialogTitle>
        </DialogHeader>
        <form onSubmit={onSubmit} className="flex flex-col gap-4">
          <Field>
            <FieldLabel>
              <Label>Zone name</Label>
            </FieldLabel>
            <FieldContent>
              <Input
                placeholder={isNew ? 'e.g. Box B2-T06' : undefined}
                value={data.name}
                onChange={(e) => set({ name: e.target.value })}
              />
            </FieldContent>
            {form.errors['storage_location.name'] && <FieldError>{form.errors['storage_location.name']}</FieldError>}
          </Field>
          <div className="grid grid-cols-2 gap-4">
            <Field>
              <FieldLabel>
                <Label>Type</Label>
              </FieldLabel>
              <FieldContent>
                <Select value={data.location_type} onValueChange={(value) => set({ location_type: value })}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {LOCATION_TYPES.map((t) => (
                      <SelectItem key={t} value={t}>{typeMeta(t).label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FieldContent>
            </Field>
            <Field>
              <FieldLabel>
                {isNew ? (
                  <Label>Parent zone</Label>
                ) : (
                  <Label>Parent zone <span className="font-normal text-muted-foreground">(move)</span></Label>
                )}
              </FieldLabel>
              <FieldContent>
                <StorageLocationSelect
                  locations={zones}
                  value={data.parent_id}
                  onValueChange={(value) => set({ parent_id: value })}
                  noneLabel="— Root (none) —"
                  exclude={excludeIds}
                />
              </FieldContent>
            </Field>
          </div>
          <Field>
            <FieldLabel>
              <Label>Code <span className="font-normal text-muted-foreground">(optional)</span></Label>
            </FieldLabel>
            <FieldContent>
              <Input
                placeholder={data.location_type === 'bag' ? 'From the box code and bag number' : isNew ? 'e.g. B2-T06' : undefined}
                value={data.location_type === 'bag' ? '' : data.code}
                disabled={data.location_type === 'bag'}
                onChange={(e) => set({ code: e.target.value })}
              />
            </FieldContent>
            {data.location_type === 'bag' && (
              <p className="text-xs text-muted-foreground">
                A bag goes inside a box with a code, and is numbered after the box’s last bag (A-1, A-2…).
              </p>
            )}
            {form.errors['storage_location.code'] && <FieldError>{form.errors['storage_location.code']}</FieldError>}
          </Field>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button type="submit" disabled={form.processing}>{isNew ? 'Create zone' : 'Save'}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
