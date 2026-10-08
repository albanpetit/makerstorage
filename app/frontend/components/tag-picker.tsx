import { router } from '@inertiajs/react'
import { FormEvent, useEffect, useState } from 'react'
import { Plus, Check } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
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

export interface TagOption {
  id: number
  name: string
  color: string | null
}

interface TagPickerProps {
  tags: TagOption[]
  value: number[]
  onChange: (value: number[]) => void
}

// Preset swatches for a newly created tag. The leading `null` is "no color";
// every other value is a #RRGGBB hex the Tag model accepts.
const PRESET_COLORS: Array<{ value: string | null; className: string }> = [
  { value: null, className: 'bg-muted' },
  { value: '#EF4444', className: 'bg-red-500' },
  { value: '#F97316', className: 'bg-orange-500' },
  { value: '#EAB308', className: 'bg-yellow-500' },
  { value: '#22C55E', className: 'bg-green-500' },
  { value: '#3B82F6', className: 'bg-blue-500' },
  { value: '#8B5CF6', className: 'bg-violet-500' },
  { value: '#EC4899', className: 'bg-pink-500' },
  { value: '#64748B', className: 'bg-slate-500' },
]

export function TagPicker({ tags, value, onChange }: TagPickerProps) {
  const [open, setOpen] = useState(false)
  const [name, setName] = useState('')
  const [color, setColor] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [processing, setProcessing] = useState(false)
  // Name of the tag we just asked the server to create; once the refreshed
  // `tags` prop contains it, we auto-select it.
  const [pendingName, setPendingName] = useState<string | null>(null)

  const toggle = (id: number) => {
    onChange(value.includes(id) ? value.filter((v) => v !== id) : [...value, id])
  }

  // Once the server round-trip refreshes the `tags` prop with the name we just
  // submitted, select it and close the dialog. Driving this off the prop keeps
  // it correct regardless of Inertia callback timing.
  useEffect(() => {
    if (!pendingName) return
    const created = tags.find((t) => t.name === pendingName)
    if (created) {
      if (!value.includes(created.id)) onChange([...value, created.id])
      setPendingName(null)
      setOpen(false)
      setName('')
      setColor(null)
    }
  }, [tags, pendingName, value, onChange])

  const submit = (e: FormEvent) => {
    e.preventDefault()
    const trimmed = name.trim()
    if (!trimmed) {
      setError('Name is required.')
      return
    }

    // Already exists (e.g. typed instead of picked): just select it.
    const existing = tags.find((t) => t.name.toLowerCase() === trimmed.toLowerCase())
    if (existing) {
      if (!value.includes(existing.id)) onChange([...value, existing.id])
      setOpen(false)
      setName('')
      setColor(null)
      return
    }

    setProcessing(true)
    setError(null)
    setPendingName(trimmed)
    router.post(
      '/tags',
      { tag: { name: trimmed, color } },
      {
        preserveScroll: true,
        preserveState: true,
        onError: (errors) => {
          setPendingName(null)
          const raw = (errors.name ?? errors.base) as string | string[] | undefined
          const message = Array.isArray(raw) ? raw[0] : raw
          setError(message ?? 'Could not create the tag.')
        },
        onFinish: () => setProcessing(false),
      }
    )
  }

  return (
    <>
      <div className="flex flex-wrap items-center gap-2">
        {tags.map((tag) => {
          const selected = value.includes(tag.id)
          return (
            <Button
              key={tag.id}
              type="button"
              variant="ghost"
              aria-pressed={selected}
              onClick={() => toggle(tag.id)}
              className="h-auto rounded-md p-0 hover:bg-transparent"
            >
              <Badge
                variant={selected ? 'default' : 'outline'}
                className="cursor-pointer gap-1.5"
                style={!selected && tag.color ? { borderColor: tag.color } : undefined}
              >
                {selected ? (
                  <Check className="size-3" />
                ) : (
                  <span
                    className="size-2 rounded-full border"
                    style={{ backgroundColor: tag.color || 'var(--muted)' }}
                  />
                )}
                {tag.name}
              </Badge>
            </Button>
          )
        })}
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="h-6 gap-1 px-2"
          onClick={() => {
            setError(null)
            setName('')
            setColor(null)
            setOpen(true)
          }}
        >
          <Plus className="size-3" />
          New tag
        </Button>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-sm">
          <form onSubmit={submit}>
            <DialogHeader>
              <DialogTitle>New tag</DialogTitle>
              <DialogDescription>Add a tag to label this part.</DialogDescription>
            </DialogHeader>

            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="new-tag-name">Name</Label>
                <Input
                  id="new-tag-name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="e.g. RoHS, favorite"
                  autoFocus
                />
                {error && <p className="text-sm text-destructive">{error}</p>}
              </div>

              <div className="space-y-2">
                <Label>Color</Label>
                <div className="flex flex-wrap gap-2">
                  {PRESET_COLORS.map((preset) => (
                    <button
                      key={preset.value ?? 'none'}
                      type="button"
                      onClick={() => setColor(preset.value)}
                      aria-label={preset.value ?? 'No color'}
                      className={`size-6 rounded-full border ${preset.className} ${
                        color === preset.value ? 'ring-2 ring-ring ring-offset-2 ring-offset-background' : ''
                      }`}
                    />
                  ))}
                </div>
              </div>
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={processing}>
                Create tag
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  )
}
