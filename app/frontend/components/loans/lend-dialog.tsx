import { FormEvent, useMemo, useState } from 'react'
import { router } from '@inertiajs/react'
import { Plus, Trash2 } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Combobox, type ComboboxOption } from '@/components/ui/combobox'
import { StorageLocationSelect } from '@/components/storage-location-select'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

import type { LendablePart, MemberOption } from './types'
import { t } from '@/lib/i18n'

interface LendDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  members: MemberOption[]
  parts: LendablePart[]
  defaultDueOn: string
  initialPartId?: number | null
}

interface LineDraft {
  key: number
  partId: string
  locationId: string
  quantity: string
}

// Who borrows and what: a member (picked) or anyone else (typed), a due date,
// and one line per part taken from one zone. Remount (via `key`) to start
// from a blank form.
export function LendDialog({ open, onOpenChange, members, parts, defaultDueOn, initialPartId }: LendDialogProps) {
  const partsById = useMemo(() => new Map(parts.map((p) => [p.id, p])), [parts])
  const firstLine = (partId?: number | null): LineDraft => {
    const part = partId ? partsById.get(partId) : undefined
    return { key: Date.now(), partId: part ? String(part.id) : '', locationId: part?.locations[0] ? String(part.locations[0].id) : '', quantity: '1' }
  }

  const [borrowerMode, setBorrowerMode] = useState<'member' | 'other'>(members.length > 0 ? 'member' : 'other')
  const [borrowerId, setBorrowerId] = useState('')
  const [borrowerName, setBorrowerName] = useState('')
  const [contact, setContact] = useState('')
  const [dueOn, setDueOn] = useState(defaultDueOn)
  const [notes, setNotes] = useState('')
  const [lines, setLines] = useState<LineDraft[]>(() => [firstLine(initialPartId)])
  const [processing, setProcessing] = useState(false)

  const memberOptions = useMemo<ComboboxOption[]>(
    () => members.map((m) => ({ value: String(m.id), label: m.name, description: m.email !== m.name ? m.email : undefined })),
    [members]
  )
  const partOptions = useMemo<ComboboxOption[]>(
    () => parts.map((p) => ({
      value: String(p.id),
      label: p.name,
      hint: p.ipn ?? (p.reference !== p.name ? p.reference : undefined),
      keywords: [p.ipn, p.reference].filter((k): k is string => Boolean(k)),
    })),
    [parts]
  )

  const updateLine = (key: number, changes: Partial<LineDraft>) =>
    setLines((current) => current.map((line) => (line.key === key ? { ...line, ...changes } : line)))

  const pickPart = (key: number, partId: string) => {
    const part = partsById.get(Number(partId))
    updateLine(key, { partId, locationId: part?.locations[0] ? String(part.locations[0].id) : '' })
  }

  const borrowerReady = borrowerMode === 'member' ? borrowerId !== '' : borrowerName.trim() !== ''
  const linesReady = lines.length > 0 && lines.every((l) => l.partId && l.locationId && Number(l.quantity) > 0)

  const submit = (e: FormEvent) => {
    e.preventDefault()
    if (!borrowerReady || !linesReady) return

    setProcessing(true)
    router.post(
      '/loans',
      {
        loan: {
          borrower_id: borrowerMode === 'member' ? borrowerId : '',
          borrower_name: borrowerMode === 'other' ? borrowerName.trim() : '',
          borrower_contact: contact.trim(),
          due_on: dueOn,
          notes: notes.trim(),
          lines: lines.map((l) => ({ part_id: l.partId, storage_location_id: l.locationId, quantity: l.quantity })),
        },
      },
      {
        onSuccess: () => onOpenChange(false),
        onFinish: () => setProcessing(false),
      }
    )
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-2xl">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{t('Lend items')}</DialogTitle>
            <DialogDescription>
              {t('The items leave stock now and go back where they came from when returned.')}
            </DialogDescription>
          </DialogHeader>

          <div className="max-h-[65vh] space-y-5 overflow-y-auto py-4 pr-1">
            <div className="space-y-2">
              <Label>{t('Borrower')}</Label>
              {members.length > 0 && (
                <div className="grid grid-cols-2 gap-1 rounded-lg bg-muted p-1">
                  <Button type="button" size="sm" variant={borrowerMode === 'member' ? 'default' : 'ghost'} onClick={() => setBorrowerMode('member')}>
                    {t('A member')}
                  </Button>
                  <Button type="button" size="sm" variant={borrowerMode === 'other' ? 'default' : 'ghost'} onClick={() => setBorrowerMode('other')}>
                    {t('Someone else')}
                  </Button>
                </div>
              )}
              {borrowerMode === 'member' ? (
                <Combobox
                  id="loan-borrower"
                  options={memberOptions}
                  value={borrowerId}
                  onValueChange={setBorrowerId}
                  placeholder={t('Pick a member')}
                  searchPlaceholder={t('Search members…')}
                  className="w-full"
                />
              ) : (
                <Input
                  id="loan-borrower-name"
                  aria-label={t('Borrower name')}
                  value={borrowerName}
                  onChange={(e) => setBorrowerName(e.target.value)}
                  placeholder={t('Name')}
                  maxLength={255}
                />
              )}
            </div>

            <div className="grid gap-3 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="loan-contact">{t('Contact')}</Label>
                <Input
                  id="loan-contact"
                  value={contact}
                  onChange={(e) => setContact(e.target.value)}
                  placeholder={borrowerMode === 'member' ? t('Their email by default') : t('Email or phone (optional)')}
                  maxLength={255}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="loan-due">{t('Due back')}</Label>
                <Input id="loan-due" type="date" value={dueOn} onChange={(e) => setDueOn(e.target.value)} />
                <p className="text-xs text-muted-foreground">{t('Clear it for a loan with no due date.')}</p>
              </div>
            </div>

            <div className="space-y-2">
              <Label>{t('Items')}</Label>
              {parts.length === 0 ? (
                <p className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">
                  {t('Nothing is in stock to lend.')}
                </p>
              ) : (
                <div className="space-y-3">
                  {lines.map((line, index) => {
                    const part = partsById.get(Number(line.partId))
                    const location = part?.locations.find((l) => String(l.id) === line.locationId)
                    return (
                      <div key={line.key} className="space-y-2 rounded-lg border p-3">
                        <div className="flex items-center gap-2">
                          <Combobox
                            id={`loan-part-${index}`}
                            options={partOptions}
                            value={line.partId}
                            onValueChange={(value) => pickPart(line.key, value)}
                            placeholder={t('Pick a part or tool')}
                            searchPlaceholder={t('Search parts…')}
                            className="min-w-0 flex-1"
                          />
                          <Button
                            type="button"
                            variant="ghost"
                            size="icon-sm"
                            aria-label={t('Remove item')}
                            disabled={lines.length === 1}
                            onClick={() => setLines((current) => current.filter((l) => l.key !== line.key))}
                          >
                            <Trash2 className="size-4 text-muted-foreground" />
                          </Button>
                        </div>
                        {part && (
                          <div className="grid gap-2 sm:grid-cols-[1fr_7rem]">
                            <StorageLocationSelect
                              locations={part.locations.map((l) => ({ id: l.id, name: l.name, hint: `${l.quantity}` }))}
                              value={line.locationId}
                              onValueChange={(value) => updateLine(line.key, { locationId: value })}
                              placeholder={t('Taken from')}
                            />
                            <Input
                              type="number"
                              min={1}
                              max={location?.quantity}
                              aria-label={t('Quantity')}
                              value={line.quantity}
                              onChange={(e) => updateLine(line.key, { quantity: e.target.value })}
                            />
                          </div>
                        )}
                      </div>
                    )
                  })}
                  <Button type="button" variant="outline" size="sm" onClick={() => setLines((current) => [...current, firstLine()])}>
                    <Plus className="size-4" />
                    {t('Add an item')}
                  </Button>
                </div>
              )}
            </div>

            <div className="space-y-2">
              <Label htmlFor="loan-notes">{t('Notes')}</Label>
              <Textarea
                id="loan-notes"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder={t('What it\'s for, accessories handed over…')}
                rows={2}
              />
            </div>
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              {t('Cancel')}
            </Button>
            <Button type="submit" disabled={processing || !borrowerReady || !linesReady}>
              {t('Lend')}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
