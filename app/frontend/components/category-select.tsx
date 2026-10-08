import { router } from '@inertiajs/react'
import { FormEvent, useEffect, useState } from 'react'
import { Plus } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { ColorSwatches } from '@/components/color-swatches'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
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

export interface CategoryOption {
  id: number
  name: string
}

interface CategorySelectProps {
  categories: CategoryOption[]
  value: string
  onValueChange: (value: string) => void
}

export function CategorySelect({ categories, value, onValueChange }: CategorySelectProps) {
  const [open, setOpen] = useState(false)
  const [name, setName] = useState('')
  const [color, setColor] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [processing, setProcessing] = useState(false)
  // Name of the category we just asked the server to create; once the
  // refreshed `categories` prop contains it, we auto-select it.
  const [pendingName, setPendingName] = useState<string | null>(null)

  // Once the server round-trip refreshes the `categories` prop with the name
  // we just submitted, select it and close the dialog. Driving this off the
  // prop (rather than the visit's onSuccess) keeps it correct regardless of
  // Inertia callback timing.
  useEffect(() => {
    if (!pendingName) return
    const created = categories.find((c) => c.name === pendingName)
    if (created) {
      onValueChange(String(created.id))
      setPendingName(null)
      setOpen(false)
      setName('')
      setColor(null)
    }
  }, [categories, pendingName, onValueChange])

  const submit = (e: FormEvent) => {
    e.preventDefault()
    const trimmed = name.trim()
    if (!trimmed) {
      setError('Name is required.')
      return
    }

    // Already exists (e.g. typed instead of picked): just select it.
    const existing = categories.find((c) => c.name.toLowerCase() === trimmed.toLowerCase())
    if (existing) {
      onValueChange(String(existing.id))
      setOpen(false)
      setName('')
      setColor(null)
      return
    }

    setProcessing(true)
    setError(null)
    setPendingName(trimmed)
    router.post(
      '/categories',
      { category: { name: trimmed, color } },
      {
        preserveScroll: true,
        preserveState: true,
        onError: (errors) => {
          setPendingName(null)
          const raw = (errors.name ?? errors.base) as string | string[] | undefined
          const message = Array.isArray(raw) ? raw[0] : raw
          setError(message ?? 'Could not create the category.')
        },
        onFinish: () => setProcessing(false),
      }
    )
  }

  return (
    <>
      <div className="flex gap-2">
        <Select value={value} onValueChange={onValueChange}>
          <SelectTrigger className="flex-1">
            <SelectValue placeholder="Select a category" />
          </SelectTrigger>
          <SelectContent>
            {categories.length === 0 ? (
              <div className="px-2 py-1.5 text-sm text-muted-foreground">No category yet</div>
            ) : (
              categories.map((category) => (
                <SelectItem key={category.id} value={category.id.toString()}>
                  {category.name}
                </SelectItem>
              ))
            )}
          </SelectContent>
        </Select>
        <Button
          type="button"
          variant="outline"
          size="icon"
          onClick={() => {
            setError(null)
            setOpen(true)
          }}
          aria-label="Create a new category"
        >
          <Plus className="size-4" />
        </Button>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-sm">
          <form onSubmit={submit}>
            <DialogHeader>
              <DialogTitle>New category</DialogTitle>
              <DialogDescription>Add a category to classify this part.</DialogDescription>
            </DialogHeader>

            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="new-category-name">Name</Label>
                <Input
                  id="new-category-name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="e.g. Resistors"
                  autoFocus
                />
                {error && <p className="text-sm text-destructive">{error}</p>}
              </div>

              <div className="space-y-2">
                <Label>Color</Label>
                <ColorSwatches value={color} onChange={setColor} />
              </div>
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={processing}>
                Create category
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  )
}
