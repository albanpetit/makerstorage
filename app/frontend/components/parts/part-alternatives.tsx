import { router } from '@inertiajs/react'
import { FormEvent, useEffect, useMemo, useState } from 'react'
import { Link2, Plus, Sparkles, Unlink } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Combobox, type ComboboxOption } from '@/components/ui/combobox'
import { Field, FieldContent, FieldLabel } from '@/components/ui/field'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { t, intlLocale } from '@/lib/i18n'

export interface AlternativePart {
  id: number
  reference: string
  name: string
  mpn: string | null
  manufacturer: string | null
  value: string | null
  footprint: string | null
  status: 'active' | 'discontinued' | 'obsolete'
  total_quantity: number
}

// A linked alternative (PartAlternative): +id+ is the link's.
export interface AlternativeLink {
  id: number
  note: string | null
  part: AlternativePart
}

// A part PartEquivalents suggests: parameters with the same value, a better
// rating or tolerance, and those it has no value for.
export interface Equivalent {
  part: AlternativePart
  matched: string[]
  better: string[]
  missing: string[]
}

interface PickablePart {
  id: number
  name: string
  mpn: string | null
  sku: string | null
  ipn: string | null
  value: string | null
}

interface PartAlternativesProps {
  partId: number
  alternatives: AlternativeLink[]
  equivalents: Equivalent[]
  canWrite: boolean
  // Called once a link is added or removed, to refresh the sheet.
  onChange: () => void
  // Shows another part in the sheet.
  onOpenPart: (id: number) => void
}

function stockClass(quantity: number) {
  return quantity > 0
    ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400'
    : 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400'
}

function PartLine({ part, onOpenPart }: { part: AlternativePart; onOpenPart: (id: number) => void }) {
  const details = [part.manufacturer, part.value, part.footprint].filter(Boolean).join(' · ')
  return (
    <Button
      type="button"
      variant="link"
      className="h-auto min-w-0 flex-1 flex-col items-start gap-0 p-0 text-left text-foreground"
      onClick={() => onOpenPart(part.id)}
    >
      <span className="max-w-full truncate font-mono text-sm font-medium">{part.reference}</span>
      <span className="max-w-full truncate text-xs font-normal text-muted-foreground">
        {part.reference !== part.name ? part.name : ''}
        {part.reference !== part.name && details ? ' · ' : ''}
        {details}
      </span>
    </Button>
  )
}

// The parts that can stand in for this one: the ones linked by hand (both
// ways), then equivalents suggested from the parameters, which writers can
// link in one click.
export function PartAlternatives({ partId, alternatives, equivalents, canWrite, onChange, onOpenPart }: PartAlternativesProps) {
  const [linkOpen, setLinkOpen] = useState(false)
  const [busy, setBusy] = useState(false)

  const link = (alternativeId: number, note = '', done?: () => void) => {
    setBusy(true)
    router.post(`/parts/${partId}/alternatives`, { alternative_part_id: alternativeId, note }, {
      preserveScroll: true,
      preserveState: true,
      onFinish: () => {
        setBusy(false)
        done?.()
        onChange()
      },
    })
  }

  const unlink = (entry: AlternativeLink) => {
    setBusy(true)
    router.delete(`/parts/${partId}/alternatives/${entry.id}`, {
      preserveScroll: true,
      preserveState: true,
      onFinish: () => {
        setBusy(false)
        onChange()
      },
    })
  }

  return (
    <div>
      <div className="mb-2 flex items-center justify-between">
        <h3 className="text-sm font-semibold">{t('Alternatives')}</h3>
        {canWrite && (
          <Button size="sm" variant="ghost" className="h-7" disabled={busy} onClick={() => setLinkOpen(true)}>
            <Plus className="size-3.5" />
            {t('Link a part')}
          </Button>
        )}
      </div>

      {alternatives.length === 0 ? (
        <p className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">
          {t('No alternative linked. Link parts that can replace this one (a second source, another maker).')}
        </p>
      ) : (
        <ul className="divide-y rounded-lg border">
          {alternatives.map((entry) => (
            <li key={entry.id} className="flex items-center gap-2 px-3 py-2 text-sm">
              <Link2 className="size-4 shrink-0 text-muted-foreground" />
              <div className="flex min-w-0 flex-1 flex-col">
                <PartLine part={entry.part} onOpenPart={onOpenPart} />
                {entry.note && <span className="truncate text-xs italic text-muted-foreground" title={entry.note}>{entry.note}</span>}
              </div>
              {entry.part.status !== 'active' && <Badge variant="outline" className="shrink-0">{entry.part.status === 'obsolete' ? t('Obsolete') : t('Discontinued')}</Badge>}
              <span className={`shrink-0 rounded-full px-2 py-0.5 font-mono text-xs font-semibold ${stockClass(entry.part.total_quantity)}`}>
                {entry.part.total_quantity.toLocaleString(intlLocale())}
              </span>
              {canWrite && (
                <Button
                  variant="ghost"
                  size="icon-sm"
                  disabled={busy}
                  aria-label={t('Unlink {name}', { name: entry.part.reference })}
                  onClick={() => unlink(entry)}
                >
                  <Unlink className="size-4 text-muted-foreground" />
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}

      {equivalents.length > 0 && (
        <div className="mt-3">
          <div className="mb-1.5 flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
            <Sparkles className="size-3.5" />
            {t('Suggested from parameters')}
          </div>
          <ul className="divide-y rounded-lg border border-dashed">
            {equivalents.map((entry) => (
              <li key={entry.part.id} className="flex items-center gap-2 px-3 py-2 text-sm">
                <div className="flex min-w-0 flex-1 flex-col gap-1">
                  <PartLine part={entry.part} onOpenPart={onOpenPart} />
                  <div className="flex flex-wrap gap-1">
                    {entry.matched.map((name) => (
                      <Badge key={`m-${name}`} variant="outline" className="text-[11px] font-normal">= {name}</Badge>
                    ))}
                    {entry.better.map((name) => (
                      <Badge key={`b-${name}`} variant="outline" className="border-emerald-300 text-[11px] font-normal text-emerald-700 dark:border-emerald-800 dark:text-emerald-400" title={t('Better rating')}>
                        ↑ {name}
                      </Badge>
                    ))}
                    {entry.missing.map((name) => (
                      <Badge key={`x-${name}`} variant="outline" className="text-[11px] font-normal text-muted-foreground" title={t('Not filled in on this part')}>
                        ? {name}
                      </Badge>
                    ))}
                  </div>
                </div>
                <span className={`shrink-0 rounded-full px-2 py-0.5 font-mono text-xs font-semibold ${stockClass(entry.part.total_quantity)}`}>
                  {entry.part.total_quantity.toLocaleString(intlLocale())}
                </span>
                {canWrite && (
                  <Button variant="outline" size="sm" className="h-7 shrink-0" disabled={busy} onClick={() => link(entry.part.id)}>
                    {t('Link')}
                  </Button>
                )}
              </li>
            ))}
          </ul>
        </div>
      )}

      {canWrite && (
        <LinkAlternativeDialog
          key={linkOpen ? 'open' : 'closed'}
          partId={partId}
          open={linkOpen}
          busy={busy}
          onOpenChange={setLinkOpen}
          onLink={(id, note) => link(id, note, () => setLinkOpen(false))}
        />
      )}
    </div>
  )
}

function LinkAlternativeDialog({ partId, open, busy, onOpenChange, onLink }: {
  partId: number
  open: boolean
  busy: boolean
  onOpenChange: (open: boolean) => void
  onLink: (id: number, note: string) => void
}) {
  const [parts, setParts] = useState<PickablePart[] | null>(null)
  const [choice, setChoice] = useState('')
  const [note, setNote] = useState('')

  // The pick-list is only fetched when the dialog opens.
  useEffect(() => {
    if (!open) return
    let cancelled = false
    fetch(`/parts/${partId}/alternatives`, { headers: { Accept: 'application/json' } })
      .then((res) => (res.ok ? res.json() : { parts: [] }))
      .then((body: { parts: PickablePart[] }) => { if (!cancelled) setParts(body.parts) })
      .catch(() => { if (!cancelled) setParts([]) })
    return () => { cancelled = true }
  }, [open, partId])

  const options = useMemo<ComboboxOption[]>(
    () => (parts ?? []).map((part) => ({
      value: String(part.id),
      label: part.name,
      description: [part.mpn, part.value].filter(Boolean).join(' · ') || undefined,
      keywords: [part.sku, part.ipn].filter((k): k is string => Boolean(k)),
      hint: part.ipn ?? undefined,
    })),
    [parts]
  )

  const submit = (e: FormEvent) => {
    e.preventDefault()
    if (choice) onLink(Number(choice), note.trim())
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={submit} className="flex flex-col gap-4">
          <DialogHeader>
            <DialogTitle>{t('Link an alternative')}</DialogTitle>
            <DialogDescription>{t('The link works both ways: this part is listed as an alternative on the other one too.')}</DialogDescription>
          </DialogHeader>
          <Field>
            <FieldLabel htmlFor="alternative-part">{t('Part')}</FieldLabel>
            <FieldContent>
              <Combobox
                id="alternative-part"
                options={options}
                value={choice}
                onValueChange={setChoice}
                placeholder={parts === null ? t('Loading…') : t('Pick a part')}
                searchPlaceholder={t('Search parts…')}
                disabled={parts === null}
              />
            </FieldContent>
          </Field>
          <Field>
            <FieldLabel htmlFor="alternative-note">{t('Note (optional)')}</FieldLabel>
            <FieldContent>
              <Input
                id="alternative-note"
                value={note}
                maxLength={200}
                placeholder={t('e.g. check the pinout, 50 V instead of 25 V')}
                onChange={(e) => setNote(e.target.value)}
              />
            </FieldContent>
          </Field>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>{t('Cancel')}</Button>
            <Button type="submit" disabled={!choice || busy}>{t('Link')}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
