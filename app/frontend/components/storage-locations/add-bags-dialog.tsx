import { FormEvent, useState } from 'react'
import { router } from '@inertiajs/react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Field, FieldContent, FieldLabel } from '@/components/ui/field'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

import type { StorageLocationRecord } from './types'
import { t, tx } from '@/lib/i18n'

interface AddBagsDialogProps {
  box: StorageLocationRecord
  bagCount: number
  separator: string
  open: boolean
  onOpenChange: (open: boolean) => void
}

// Box & bag storage: appends numbered bags to a box (A-1, A-2, …).
export function AddBagsDialog({ box, bagCount, separator, open, onOpenChange }: AddBagsDialogProps) {
  const [count, setCount] = useState('10')
  const [processing, setProcessing] = useState(false)
  const n = Number(count) || 0
  const first = `${box.code}${separator}${bagCount + 1}`
  const last = `${box.code}${separator}${bagCount + n}`

  const submit = (e: FormEvent) => {
    e.preventDefault()
    router.post(`/storage_locations/${box.id}/add_bags`, { count: n }, {
      preserveScroll: true,
      onStart: () => setProcessing(true),
      onFinish: () => setProcessing(false),
      onSuccess: () => onOpenChange(false),
    })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t('Add bags to {name}', { name: box.name })}</DialogTitle>
          <DialogDescription>
            {box.code
              ? t('Each bag is numbered after the last one in the box; its code becomes the reference of the part stored in it.')
              : t('Give this box a code (A, B, C…) first: bags are numbered from it.')}
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="flex flex-col gap-4">
          <Field>
            <FieldLabel>
              <Label>{t('Number of bags')}</Label>
            </FieldLabel>
            <FieldContent>
              <Input
                inputMode="numeric"
                value={count}
                onChange={(e) => setCount(e.target.value.replace(/[^0-9]/g, '').slice(0, 3))}
              />
            </FieldContent>
            {box.code && n > 0 && (
              <p className="text-xs text-muted-foreground">
                {n === 1
                  ? tx('Creates {code}.', { code: <span className="font-mono">{first}</span> })
                  : tx('Creates {first} to {last}.', { first: <span className="font-mono">{first}</span>, last: <span className="font-mono">{last}</span> })}
              </p>
            )}
          </Field>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>{t('Cancel')}</Button>
            <Button type="submit" disabled={processing || !box.code || n < 1 || n > 200}>{t('Add bags')}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
