import { useEffect, useMemo, useState } from 'react'
import { Combobox, type ComboboxOption } from '@/components/ui/combobox'
import { t } from '@/lib/i18n'

export interface PickedPart {
  id: number
  reference: string | null
  name: string
  unit: string
  pack_size: number | null
}

interface PartPickerProps {
  value: string
  onPick: (part: PickedPart | null) => void
  id?: string
  placeholder?: string
  className?: string
}

// Picks a part of the organization, searched on the server (GET
// /parts/options, the first 20 matches) a moment after typing stops, so a
// page never has to ship the whole inventory for one picker.
export function PartPicker({ value, onPick, id, placeholder, className }: PartPickerProps) {
  const [parts, setParts] = useState<PickedPart[] | null>(null)
  const [picked, setPicked] = useState<PickedPart | null>(null)
  const [query, setQuery] = useState('')

  useEffect(() => {
    let cancelled = false
    const timer = setTimeout(() => {
      fetch(`/parts/options?q=${encodeURIComponent(query.trim())}`, { headers: { Accept: 'application/json' } })
        .then((res) => (res.ok ? res.json() : { parts: [] }))
        .then((body: { parts: PickedPart[] }) => { if (!cancelled) setParts(body.parts) })
        .catch(() => { if (!cancelled) setParts([]) })
    }, query ? 250 : 0)
    return () => {
      cancelled = true
      clearTimeout(timer)
    }
  }, [query])

  // The picked part stays an option while other searches come back; a value
  // cleared by the parent (form reset) drops it.
  const current = picked && String(picked.id) === value ? picked : null
  const options = useMemo<ComboboxOption[]>(() => {
    const list = [...(parts ?? [])]
    if (current && !list.some((part) => part.id === current.id)) list.unshift(current)
    return list.map((part) => ({
      value: String(part.id),
      label: part.reference ? `${part.reference} · ${part.name}` : part.name,
    }))
  }, [parts, current])

  const pick = (next: string) => {
    const part = [...(parts ?? []), ...(current ? [current] : [])].find((option) => String(option.id) === next) ?? null
    setPicked(part)
    onPick(part)
  }

  return (
    <Combobox
      id={id}
      options={options}
      value={value}
      onValueChange={pick}
      onQueryChange={setQuery}
      placeholder={parts === null ? t('Loading…') : (placeholder ?? t('Select a part'))}
      searchPlaceholder={t('Search parts…')}
      className={className}
    />
  )
}
