import { Head, router, useForm } from '@inertiajs/react'
import { FormEvent, useMemo, useState } from 'react'
import { Plus, Tag as TagIcon, Pencil, Trash2 } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { Button } from '@/components/ui/button'
import { ColorSwatches } from '@/components/color-swatches'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'

interface Tag {
  id: number
  name: string
  color: string | null
  description: string | null
  parts_count: number
}

interface TagsPageProps {
  tags: Tag[]
}

interface TagFormData {
  tag: {
    name: string
    color: string
    description: string
  }
}

const EMPTY_FORM: TagFormData['tag'] = {
  name: '', color: '', description: '',
}

export default function TagsIndex({ tags }: TagsPageProps) {
  const { canWrite } = usePermissions()
  const [newOpen, setNewOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [deleteId, setDeleteId] = useState<number | null>(null)

  const editing = editId != null ? tags.find((t) => t.id === editId) : undefined
  const deleting = deleteId != null ? tags.find((t) => t.id === deleteId) : undefined

  const newForm = useForm<TagFormData>({ tag: EMPTY_FORM })
  const editForm = useForm<TagFormData>({ tag: EMPTY_FORM })

  const stats = useMemo(() => {
    const withParts = tags.filter((t) => t.parts_count > 0).length
    const totalTagged = tags.reduce((sum, t) => sum + t.parts_count, 0)
    return [
      { label: 'Tags', value: String(tags.length) },
      { label: 'In use', value: String(withParts) },
      { label: 'Tagged parts', value: String(totalTagged) },
    ]
  }, [tags])

  const openNewDialog = () => {
    newForm.reset()
    newForm.clearErrors()
    setNewOpen(true)
  }

  const submitNew = (e: FormEvent) => {
    e.preventDefault()
    newForm.post('/tags', {
      preserveScroll: true,
      onSuccess: () => setNewOpen(false),
    })
  }

  const openEditDialog = (tag: Tag) => {
    editForm.clearErrors()
    editForm.setData('tag', {
      name: tag.name,
      color: tag.color || '',
      description: tag.description || '',
    })
    setEditId(tag.id)
  }

  const submitEdit = (e: FormEvent) => {
    e.preventDefault()
    if (!editing) return
    editForm.patch(`/tags/${editing.id}`, {
      preserveScroll: true,
      onSuccess: () => setEditId(null),
    })
  }

  const confirmDelete = () => {
    if (!deleting) return
    router.delete(`/tags/${deleting.id}`, {
      preserveScroll: true,
      onSuccess: () => setDeleteId(null),
    })
  }

  return (
    <AppLayout
      header={
        <PageHeader title="Tags" subtitle="Label parts with cross-cutting keywords">
          {canWrite && (
            <Button size="sm" onClick={openNewDialog}>
              <Plus className="size-4" />
              Add Tag
            </Button>
          )}
        </PageHeader>
      }
    >
      <Head title="Tags" />

      <div className="space-y-6">
        <FlashMessages />

        {/* Stats */}
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3">
          {stats.map((stat) => (
            <Card key={stat.label}>
              <CardContent className="flex items-center justify-between">
                <div>
                  <div className="text-sm text-muted-foreground">{stat.label}</div>
                  <div className="mt-1 font-mono text-2xl font-bold">{stat.value}</div>
                </div>
                <TagIcon className="size-5 text-muted-foreground" />
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Tag table */}
        {tags.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
              <TagIcon className="size-8 text-muted-foreground" />
              <div>
                <p className="font-medium">No tags yet</p>
                <p className="text-sm text-muted-foreground">
                  {canWrite
                    ? 'Add your first tag to label parts across categories.'
                    : 'No tags have been added yet.'}
                </p>
              </div>
              {canWrite && (
                <Button onClick={openNewDialog}>
                  <Plus className="size-4" />
                  Add Tag
                </Button>
              )}
            </CardContent>
          </Card>
        ) : (
          <Card className="overflow-hidden py-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Name</TableHead>
                  <TableHead>Description</TableHead>
                  <TableHead className="text-right">Parts</TableHead>
                  {canWrite && <TableHead className="w-24" />}
                </TableRow>
              </TableHeader>
              <TableBody>
                {tags.map((tag) => (
                  <TableRow key={tag.id}>
                    <TableCell>
                      <Badge
                        variant="outline"
                        className="gap-1.5"
                        style={tag.color ? { borderColor: tag.color } : undefined}
                      >
                        <span
                          className="size-2 rounded-full border"
                          style={{ backgroundColor: tag.color || 'var(--muted)' }}
                        />
                        {tag.name}
                      </Badge>
                    </TableCell>
                    <TableCell className="max-w-xs truncate text-muted-foreground">
                      {tag.description || '-'}
                    </TableCell>
                    <TableCell className="text-right font-mono">{tag.parts_count}</TableCell>
                    {canWrite && (
                      <TableCell>
                        <div className="flex items-center justify-end gap-1">
                          <Button
                            variant="ghost"
                            size="icon-sm"
                            aria-label="Edit tag"
                            onClick={() => openEditDialog(tag)}
                          >
                            <Pencil className="size-4" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon-sm"
                            aria-label="Delete tag"
                            className="text-destructive"
                            onClick={() => setDeleteId(tag.id)}
                          >
                            <Trash2 className="size-4" />
                          </Button>
                        </div>
                      </TableCell>
                    )}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </Card>
        )}
      </div>

      {/* New tag dialog */}
      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add tag</DialogTitle>
          </DialogHeader>
          <TagForm
            data={newForm.data.tag}
            errors={{
              name: newForm.errors['tag.name'],
              color: newForm.errors['tag.color'],
              description: newForm.errors['tag.description'],
            }}
            onChange={(patch) => newForm.setData('tag', { ...newForm.data.tag, ...patch })}
            onSubmit={submitNew}
            onCancel={() => setNewOpen(false)}
            processing={newForm.processing}
            submitLabel="Add tag"
          />
        </DialogContent>
      </Dialog>

      {/* Edit tag dialog */}
      <Dialog open={editId != null} onOpenChange={(open) => !open && setEditId(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit tag</DialogTitle>
          </DialogHeader>
          <TagForm
            data={editForm.data.tag}
            errors={{
              name: editForm.errors['tag.name'],
              color: editForm.errors['tag.color'],
              description: editForm.errors['tag.description'],
            }}
            onChange={(patch) => editForm.setData('tag', { ...editForm.data.tag, ...patch })}
            onSubmit={submitEdit}
            onCancel={() => setEditId(null)}
            processing={editForm.processing}
            submitLabel="Save"
          />
        </DialogContent>
      </Dialog>

      {/* Delete confirmation */}
      <AlertDialog open={deleteId != null} onOpenChange={(open) => !open && setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete this tag?</AlertDialogTitle>
            <AlertDialogDescription>
              <span className="font-semibold text-foreground">{deleting?.name}</span> will be removed.
              {deleting && deleting.parts_count > 0 && (
                <> It will be removed from {deleting.parts_count} part{deleting.parts_count !== 1 ? 's' : ''}; the parts themselves are kept.</>
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={confirmDelete} className="bg-destructive text-white hover:bg-destructive/90">
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </AppLayout>
  )
}

interface TagFormProps {
  data: TagFormData['tag']
  errors: {
    name?: string | string[]
    color?: string | string[]
    description?: string | string[]
  }
  onChange: (patch: Partial<TagFormData['tag']>) => void
  onSubmit: (e: FormEvent) => void
  onCancel: () => void
  processing: boolean
  submitLabel: string
}

function TagForm({
  data, errors, onChange, onSubmit, onCancel, processing, submitLabel,
}: TagFormProps) {
  return (
    <form onSubmit={onSubmit} className="flex flex-col gap-4">
      <Field>
        <FieldLabel>
          <Label>Name</Label>
        </FieldLabel>
        <FieldContent>
          <Input
            placeholder="e.g. RoHS, obsolete, favorite"
            value={data.name}
            onChange={(e) => onChange({ name: e.target.value })}
          />
        </FieldContent>
        {errors.name && <FieldError>{errors.name}</FieldError>}
      </Field>

      <Field>
        <FieldLabel>
          <Label>Color</Label>
        </FieldLabel>
        <FieldContent>
          <ColorSwatches value={data.color || null} onChange={(color) => onChange({ color: color ?? '' })} />
        </FieldContent>
        {errors.color && <FieldError>{errors.color}</FieldError>}
      </Field>

      <Field>
        <FieldLabel>
          <Label>Description</Label>
        </FieldLabel>
        <FieldContent>
          <Textarea
            placeholder="Optional notes about this tag"
            value={data.description}
            onChange={(e) => onChange({ description: e.target.value })}
          />
        </FieldContent>
        {errors.description && <FieldError>{errors.description}</FieldError>}
      </Field>

      <DialogFooter>
        <Button type="button" variant="outline" onClick={onCancel}>Cancel</Button>
        <Button type="submit" disabled={processing}>{submitLabel}</Button>
      </DialogFooter>
    </form>
  )
}
