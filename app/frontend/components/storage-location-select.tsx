import { FormEvent, useMemo, useState } from 'react'

import { Button } from '@/components/ui/button'
import { Combobox, type ComboboxOption } from '@/components/ui/combobox'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { LOCATION_TYPES, typeMeta } from '@/components/storage-locations/zone-meta'
import { cn } from '@/lib/utils'

// Shape of OptionListSerializers#serialize_storage_locations: `name` is the
// full path ("Lab > Cabinet A > Box 3"), `short_name` the zone's own name.
// Lists that only carry the zone's own `name` plus `parent_id` (Storage zones
// page, orders) work too: the path is rebuilt from the parents. Plain
// `{ id, name }` lists fall back to a flat, searchable list.
export interface StorageLocationOption {
  id: number
  name: string
  short_name?: string
  parent_id?: number | null
  location_type?: string
  code?: string | null
  // Extra text at the end of the row (e.g. the quantity stored there).
  hint?: string
}

interface StorageLocationSelectProps {
  locations: StorageLocationOption[]
  value: string
  onValueChange: (value: string) => void
  id?: string
  placeholder?: string
  className?: string
  disabled?: boolean
  // Adds a first entry for "no zone" (value ''), with this label.
  noneLabel?: string
  // Zones left out of the list (e.g. a move's source, or a zone's own subtree
  // when picking its parent).
  exclude?: Iterable<number>
  // Offer "Create zone …" in the list (off by default).
  allowCreate?: boolean
}

const PATH_SEPARATOR = ' > '
const NONE = ''

interface Resolved {
  location: StorageLocationOption
  own: string
  path: string[]
}

const ownName = (location: StorageLocationOption) => location.short_name ?? location.name

function csrfToken(): string {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ?? ''
}

// Segment-wise, case-insensitive: a parent sorts right before its children.
function comparePaths(a: string[], b: string[]) {
  for (let i = 0; i < Math.min(a.length, b.length); i++) {
    const x = a[i].toLowerCase()
    const y = b[i].toLowerCase()
    if (x !== y) return x < y ? -1 : 1
  }
  return a.length - b.length
}

// Every zone with its path from the root, sorted so the list reads as a tree.
function resolve(locations: StorageLocationOption[]): Resolved[] {
  const byId = new Map(locations.map((l) => [l.id, l]))
  return locations
    .map((location) => {
      const own = ownName(location)
      // No parent info: `name` is all we have (it may already be a full path).
      if (location.parent_id === undefined) return { location, own, path: location.name.split(PATH_SEPARATOR) }

      const path = [own]
      const seen = new Set([location.id])
      let parent = location.parent_id != null ? byId.get(location.parent_id) : undefined
      while (parent && !seen.has(parent.id)) {
        seen.add(parent.id)
        path.unshift(ownName(parent))
        parent = parent.parent_id != null ? byId.get(parent.parent_id) : undefined
      }
      return { location, own, path }
    })
    .sort((a, b) => comparePaths(a.path, b.path))
}

function zoneIcon(type: string | undefined) {
  if (!type) return undefined
  const Icon = typeMeta(type).icon
  return <Icon className="size-4 shrink-0 text-muted-foreground" />
}

function toOptions(resolved: Resolved[], flat = false): ComboboxOption[] {
  return resolved.map(({ location, own, path }) => {
    const tree = !flat && location.parent_id !== undefined
    return {
      value: String(location.id),
      label: tree ? own : path.join(PATH_SEPARATOR),
      description: tree && path.length > 1 ? path.slice(0, -1).join(PATH_SEPARATOR) : undefined,
      depth: tree ? path.length - 1 : undefined,
      selectedLabel: path.join(PATH_SEPARATOR),
      keywords: location.code ? [location.code] : undefined,
      icon: zoneIcon(location.location_type),
      hint: location.hint ?? location.code ?? undefined,
    }
  })
}

// Searchable storage-zone picker used wherever a zone is chosen: the zone tree
// (indented, with type icons and codes), search over the whole path and the
// code ("cab box 3", "B2-T06"), the full path on the trigger, and optionally
// creating a zone without leaving the form.
export function StorageLocationSelect({
  locations,
  value,
  onValueChange,
  id,
  placeholder = 'Select a zone',
  className,
  disabled,
  noneLabel,
  exclude,
  allowCreate = false,
}: StorageLocationSelectProps) {
  // Zones created from here. The parent's `locations` may never refresh (e.g.
  // the part sidebar fetches its lists once), so we keep them locally.
  const [created, setCreated] = useState<StorageLocationOption[]>([])
  const [open, setOpen] = useState(false)
  const [name, setName] = useState('')
  const [locationType, setLocationType] = useState('box')
  const [parentId, setParentId] = useState(NONE)
  const [code, setCode] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [processing, setProcessing] = useState(false)

  const all = useMemo(() => {
    const extra = created.filter((c) => !locations.some((existing) => existing.id === c.id))
    return resolve(extra.length ? [...locations, ...extra] : locations)
  }, [locations, created])

  const excluded = useMemo(() => new Set(exclude ?? []), [exclude])

  const options: ComboboxOption[] = useMemo(() => {
    const zones = toOptions(all.filter((r) => !excluded.has(r.location.id)))
    return noneLabel ? [{ value: NONE, label: noneLabel }, ...zones] : zones
  }, [all, excluded, noneLabel])

  const parentOptions: ComboboxOption[] = useMemo(
    () => [
      { value: NONE, label: 'None (top level)' },
      ...toOptions(all.filter((r) => r.location.location_type !== 'bag'), true),
    ],
    [all]
  )

  // "Lab > Cabinet A > Box 3" typed in the search pre-fills the parent when
  // the path before the last segment is an existing zone.
  const startCreate = (query: string) => {
    const segments = query.split('>').map((s) => s.trim()).filter(Boolean)
    const leaf = segments.pop() ?? ''
    const parentPath = segments.join(PATH_SEPARATOR).toLowerCase()
    const parent = parentPath ? all.find((r) => r.path.join(PATH_SEPARATOR).toLowerCase() === parentPath) : undefined

    setName(parent ? leaf : query)
    setParentId(parent ? String(parent.location.id) : NONE)
    setLocationType('box')
    setCode('')
    setError(null)
    setOpen(true)
  }

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    // The picker lives inside other forms: keep this submit to itself.
    e.stopPropagation()
    const bag = locationType === 'bag'
    const trimmed = name.trim()
    if (!trimmed && !bag) {
      setError('Name is required.')
      return
    }

    setProcessing(true)
    setError(null)
    try {
      const response = await fetch('/storage_locations', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          'X-CSRF-Token': csrfToken(),
        },
        body: JSON.stringify({
          storage_location: {
            name: trimmed,
            location_type: locationType,
            parent_id: parentId || null,
            code: bag ? '' : code.trim(),
          },
        }),
      })
      const data = await response.json().catch(() => ({}))
      if (response.ok && data.storage_location) {
        const location = data.storage_location as StorageLocationOption
        setCreated((list) => [...list, location])
        onValueChange(String(location.id))
        setOpen(false)
      } else {
        const errors = (data.errors ?? {}) as Record<string, string>
        setError(errors.name ?? errors.code ?? errors.parent ?? data.error ?? Object.values(errors)[0] ?? 'Could not create the zone.')
      }
    } catch {
      setError('Could not create the zone.')
    } finally {
      setProcessing(false)
    }
  }

  return (
    <>
      <Combobox
        id={id}
        options={options}
        value={value}
        onValueChange={onValueChange}
        placeholder={placeholder}
        searchPlaceholder="Search zones or codes…"
        emptyText={all.length === 0 ? 'No storage zone yet.' : 'No matching zone.'}
        className={cn('w-full', className)}
        contentClassName="min-w-[20rem]"
        disabled={disabled}
        onCreate={allowCreate ? startCreate : undefined}
        createLabel={(query) => (query ? `Create zone "${query}"` : 'New zone…')}
      />

      {allowCreate && (
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogContent className="sm:max-w-sm">
            <form onSubmit={submit}>
              <DialogHeader>
                <DialogTitle>New storage zone</DialogTitle>
                <DialogDescription>Add a place to keep components.</DialogDescription>
              </DialogHeader>

              <div className="space-y-4 py-4">
                <div className="grid grid-cols-[1fr_8rem] gap-3">
                  <div className="min-w-0 space-y-2">
                    <Label htmlFor="new-zone-name">Name</Label>
                    <Input
                      id="new-zone-name"
                      value={name}
                      onChange={(e) => setName(e.target.value)}
                      placeholder={locationType === 'bag' ? 'From its number' : 'e.g. Box 3'}
                      autoFocus
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="new-zone-type">Type</Label>
                    <Select value={locationType} onValueChange={setLocationType}>
                      <SelectTrigger id="new-zone-type" className="w-full">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {LOCATION_TYPES.map((t) => (
                          <SelectItem key={t} value={t}>{typeMeta(t).label}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                </div>
                {error && <p className="text-sm text-destructive">{error}</p>}

                <div className="space-y-2">
                  <Label htmlFor="new-zone-parent">Inside</Label>
                  <Combobox
                    id="new-zone-parent"
                    options={parentOptions}
                    value={parentId}
                    onValueChange={setParentId}
                    searchPlaceholder="Search zones or codes…"
                    emptyText="No matching zone."
                    className="w-full"
                    contentClassName="min-w-[20rem]"
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="new-zone-code">
                    Code <span className="font-normal text-muted-foreground">(optional)</span>
                  </Label>
                  <Input
                    id="new-zone-code"
                    value={locationType === 'bag' ? '' : code}
                    disabled={locationType === 'bag'}
                    onChange={(e) => setCode(e.target.value)}
                    placeholder={locationType === 'bag' ? 'From the box code and bag number' : 'e.g. B2-T06'}
                  />
                </div>
              </div>

              <DialogFooter>
                <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                  Cancel
                </Button>
                <Button type="submit" disabled={processing}>
                  Create zone
                </Button>
              </DialogFooter>
            </form>
          </DialogContent>
        </Dialog>
      )}
    </>
  )
}
