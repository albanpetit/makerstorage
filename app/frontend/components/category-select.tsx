import { FormEvent, useMemo, useState } from 'react'

import { Button } from '@/components/ui/button'
import { ColorSwatches } from '@/components/color-swatches'
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
import { t } from '@/lib/i18n'

// Shape of OptionListSerializers#serialize_categories: `name` is the full path
// ("Passives > Resistors"), `short_name` the category's own name. The extra
// fields are optional so lists of plain `{ id, name }` still work.
export interface CategoryOption {
  id: number
  name: string
  short_name?: string
  parent_id?: number | null
  depth?: number
  code?: string | null
}

interface CategorySelectProps {
  categories: CategoryOption[]
  value: string
  onValueChange: (value: string) => void
  id?: string
  placeholder?: string
  // Offer "Create …" in the list (on by default).
  allowCreate?: boolean
}

const PATH_SEPARATOR = ' > '
const NO_PARENT = ''

const shortName = (category: CategoryOption) => category.short_name ?? category.name

function csrfToken(): string {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ?? ''
}

// Segment-wise, case-insensitive, like the server sort: a parent sorts right
// before its children.
function comparePaths(a: CategoryOption, b: CategoryOption) {
  const pa = a.name.toLowerCase().split(PATH_SEPARATOR)
  const pb = b.name.toLowerCase().split(PATH_SEPARATOR)
  for (let i = 0; i < Math.min(pa.length, pb.length); i++) {
    if (pa[i] !== pb[i]) return pa[i] < pb[i] ? -1 : 1
  }
  return pa.length - pb.length
}

export function CategorySelect({
  categories,
  value,
  onValueChange,
  id,
  placeholder = t('Select a category'),
  allowCreate = true,
}: CategorySelectProps) {
  // Categories created from here. The parent's `categories` list may never
  // refresh (e.g. the part sidebar fetches it once), so we keep them locally.
  const [created, setCreated] = useState<CategoryOption[]>([])
  const [open, setOpen] = useState(false)
  const [name, setName] = useState('')
  const [parentId, setParentId] = useState(NO_PARENT)
  const [color, setColor] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [processing, setProcessing] = useState(false)

  const all = useMemo(() => {
    const extra = created.filter((c) => !categories.some((existing) => existing.id === c.id))
    return extra.length ? [...categories, ...extra].sort(comparePaths) : categories
  }, [categories, created])

  const byId = useMemo(() => new Map(all.map((c) => [c.id, c])), [all])

  const options: ComboboxOption[] = useMemo(
    () =>
      all.map((category) => {
        const parent = category.parent_id ? byId.get(category.parent_id) : undefined
        return {
          value: String(category.id),
          label: shortName(category),
          description: parent?.name,
          depth: category.depth ?? 0,
          selectedLabel: category.name,
          keywords: category.code ? [category.code] : undefined,
        }
      }),
    [all, byId]
  )

  const parentOptions: ComboboxOption[] = useMemo(
    () => [
      { value: NO_PARENT, label: t('None (top level)') },
      ...options.map((option) => ({ ...option, label: option.selectedLabel ?? option.label, description: undefined, depth: undefined })),
    ],
    [options]
  )

  const findByName = (candidate: string) =>
    all.find((c) => shortName(c).toLowerCase() === candidate.toLowerCase())

  // "Passives > Capacitors" typed in the search pre-fills the parent when the
  // path before the last segment is an existing category.
  const startCreate = (query: string) => {
    const segments = query.split('>').map((s) => s.trim()).filter(Boolean)
    const leaf = segments.pop() ?? ''
    const parentPath = segments.join(PATH_SEPARATOR).toLowerCase()
    const parent = parentPath ? all.find((c) => c.name.toLowerCase() === parentPath) : undefined

    setName(parent ? leaf : query)
    setParentId(parent ? String(parent.id) : NO_PARENT)
    setColor(null)
    setError(null)
    setOpen(true)
  }

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    e.stopPropagation()
    const trimmed = name.trim()
    if (!trimmed) {
      setError(t('Name is required.'))
      return
    }

    // Names are unique per organization: an existing one is just selected.
    const existing = findByName(trimmed)
    if (existing) {
      onValueChange(String(existing.id))
      setOpen(false)
      return
    }

    setProcessing(true)
    setError(null)
    try {
      const response = await fetch('/categories', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          'X-CSRF-Token': csrfToken(),
        },
        body: JSON.stringify({ category: { name: trimmed, color, parent_id: parentId || null } }),
      })
      const data = await response.json().catch(() => ({}))
      if (response.ok && data.category) {
        const category = data.category as CategoryOption
        setCreated((list) => [...list, category])
        onValueChange(String(category.id))
        setOpen(false)
      } else {
        const errors = (data.errors ?? {}) as Record<string, string>
        setError(errors.name ?? errors.parent ?? data.error ?? Object.values(errors)[0] ?? t('Could not create the category.'))
      }
    } catch {
      setError(t('Could not create the category.'))
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
        searchPlaceholder={t('Search categories…')}
        emptyText={all.length === 0 ? t('No category yet.') : t('No matching category.')}
        className="w-full"
        contentClassName="min-w-[18rem]"
        onCreate={allowCreate ? startCreate : undefined}
        createLabel={(query) => (query ? t('Create category "{name}"', { name: query }) : t('New category…'))}
      />

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-sm">
          {/* The picker lives inside the part form: keep this submit from
              bubbling up to it (portals still bubble React events). */}
          <form onSubmit={submit}>
            <DialogHeader>
              <DialogTitle>{t('New category')}</DialogTitle>
              <DialogDescription>{t('Add a category to classify this part.')}</DialogDescription>
            </DialogHeader>

            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="new-category-name">{t('Name')}</Label>
                <Input
                  id="new-category-name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder={t('e.g. Resistors')}
                  autoFocus
                />
                {error && <p className="text-sm text-destructive">{error}</p>}
              </div>

              <div className="space-y-2">
                <Label htmlFor="new-category-parent">{t('Parent')}</Label>
                <Combobox
                  id="new-category-parent"
                  options={parentOptions}
                  value={parentId}
                  onValueChange={setParentId}
                  searchPlaceholder={t('Search categories…')}
                  emptyText={t('No matching category.')}
                  className="w-full"
                />
              </div>

              <div className="space-y-2">
                <Label>{t('Color')}</Label>
                <ColorSwatches value={color} onChange={setColor} />
              </div>
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                {t('Cancel')}
              </Button>
              <Button type="submit" disabled={processing}>
                {t('Create category')}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  )
}
