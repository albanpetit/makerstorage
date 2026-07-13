import { Head, router, useForm } from '@inertiajs/react'
import { FormEvent, useMemo, useState } from 'react'
import { Plus, FolderTree, Pencil, Trash2, ChevronRight } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
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

// Preset swatches. The leading `null` is "no color"; every other value is a
// #RRGGBB hex the Category model accepts.
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

const NONE_VALUE = '__none__'

interface Category {
  id: number
  name: string
  code: string | null
  color: string | null
  description: string | null
  parent_id: number | null
  parts_count: number
}

interface CategoriesPageProps {
  categories: Category[]
}

interface CategoryFormData {
  category: {
    name: string
    code: string
    color: string
    description: string
    parent_id: string
  }
}

const EMPTY_FORM: CategoryFormData['category'] = {
  name: '', code: '', color: '', description: '', parent_id: '',
}

export default function CategoriesIndex({ categories }: CategoriesPageProps) {
  const { canWrite } = usePermissions()
  const [newOpen, setNewOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [deleteId, setDeleteId] = useState<number | null>(null)
  const [reassignTarget, setReassignTarget] = useState('')

  const byId = useMemo(() => new Map(categories.map((c) => [c.id, c])), [categories])
  const editing = editId != null ? byId.get(editId) : undefined
  const deleting = deleteId != null ? byId.get(deleteId) : undefined

  const childrenOf = useMemo(() => {
    const map = new Map<number | null, Category[]>()
    for (const category of categories) {
      const key = category.parent_id
      const bucket = map.get(key) ?? []
      bucket.push(category)
      map.set(key, bucket)
    }
    return map
  }, [categories])

  const roots = childrenOf.get(null) ?? []

  // Ids that cannot be a parent of the category being edited (itself + its
  // descendants), so the form never offers a choice that would form a cycle.
  const forbiddenParentIds = useMemo(() => {
    if (!editing) return new Set<number>()
    const forbidden = new Set<number>([editing.id])
    const stack = [editing.id]
    while (stack.length > 0) {
      const current = stack.pop()!
      for (const child of childrenOf.get(current) ?? []) {
        if (!forbidden.has(child.id)) {
          forbidden.add(child.id)
          stack.push(child.id)
        }
      }
    }
    return forbidden
  }, [editing, childrenOf])

  const fullPath = (category: Category): string => {
    const parts = [category.name]
    let current = category
    while (current.parent_id != null) {
      const parent = byId.get(current.parent_id)
      if (!parent) break
      parts.unshift(parent.name)
      current = parent
    }
    return parts.join(' › ')
  }

  const parentOptions = useMemo(
    () =>
      categories
        .filter((c) => !forbiddenParentIds.has(c.id))
        .map((c) => ({ id: c.id, label: fullPath(c) }))
        .sort((a, b) => a.label.localeCompare(b.label)),
    [categories, forbiddenParentIds],
  )

  const stats = useMemo(() => {
    const rootCount = roots.length
    const withParts = categories.filter((c) => c.parts_count > 0).length
    const totalParts = categories.reduce((sum, c) => sum + c.parts_count, 0)
    return [
      { label: 'Categories', value: String(categories.length) },
      { label: 'Top-level', value: String(rootCount) },
      { label: 'In use', value: String(withParts) },
      { label: 'Classified parts', value: String(totalParts) },
    ]
  }, [categories, roots.length])

  const newForm = useForm<CategoryFormData>({ category: EMPTY_FORM })
  const editForm = useForm<CategoryFormData>({ category: EMPTY_FORM })

  const openNewDialog = (parentId?: number) => {
    newForm.reset()
    newForm.clearErrors()
    if (parentId != null) newForm.setData('category', { ...EMPTY_FORM, parent_id: String(parentId) })
    setNewOpen(true)
  }

  const submitNew = (e: FormEvent) => {
    e.preventDefault()
    newForm.transform((data) => normalize(data))
    newForm.post('/categories', {
      preserveScroll: true,
      onSuccess: () => setNewOpen(false),
    })
  }

  const openEditDialog = (category: Category) => {
    editForm.clearErrors()
    editForm.setData('category', {
      name: category.name,
      code: category.code || '',
      color: category.color || '',
      description: category.description || '',
      parent_id: category.parent_id != null ? String(category.parent_id) : '',
    })
    setEditId(category.id)
  }

  const submitEdit = (e: FormEvent) => {
    e.preventDefault()
    if (!editing) return
    editForm.transform((data) => normalize(data))
    editForm.patch(`/categories/${editing.id}`, {
      preserveScroll: true,
      onSuccess: () => setEditId(null),
    })
  }

  const openDeleteDialog = (id: number) => {
    setReassignTarget('')
    setDeleteId(id)
  }

  const confirmDelete = () => {
    if (!deleting) return
    router.delete(`/categories/${deleting.id}`, {
      preserveScroll: true,
      data: reassignTarget ? { target_category_id: reassignTarget } : {},
      onSuccess: () => {
        setDeleteId(null)
        setReassignTarget('')
      },
    })
  }

  const childCount = (id: number) => (childrenOf.get(id) ?? []).length

  // Ids of a category plus its whole subtree (everything that would be deleted).
  const subtreeIds = (id: number): number[] => {
    const ids = [id]
    const stack = [id]
    while (stack.length > 0) {
      const current = stack.pop()!
      for (const child of childrenOf.get(current) ?? []) {
        ids.push(child.id)
        stack.push(child.id)
      }
    }
    return ids
  }

  // Parts classified anywhere in the deleting subtree need a new home, and the
  // destination must live outside that subtree.
  const deletingSubtree = deleting ? subtreeIds(deleting.id) : []
  const deletingPartsCount = deletingSubtree.reduce(
    (sum, id) => sum + (byId.get(id)?.parts_count ?? 0),
    0,
  )
  const deleteTargetOptions = useMemo(() => {
    if (!deleting) return []
    const excluded = new Set(subtreeIds(deleting.id))
    return categories
      .filter((c) => !excluded.has(c.id))
      .map((c) => ({ id: c.id, label: fullPath(c) }))
      .sort((a, b) => a.label.localeCompare(b.label))
  }, [deleting, categories, childrenOf])

  const renderRows = (parentId: number | null, depth: number): React.ReactNode[] =>
    (childrenOf.get(parentId) ?? []).flatMap((category) => [
      <div
        key={category.id}
        className="flex items-center gap-3 border-b px-4 py-2.5 last:border-b-0 hover:bg-muted/50"
        style={{ paddingLeft: `${depth * 1.5 + 1}rem` }}
      >
        {depth > 0 && <ChevronRight className="size-3.5 shrink-0 text-muted-foreground" />}
        <span
          className="size-3 shrink-0 rounded-full border"
          style={{ backgroundColor: category.color || 'var(--muted)' }}
        />
        <span className="min-w-0 flex-1 truncate font-medium">{category.name}</span>
        {category.code && (
          <Badge variant="outline" className="shrink-0 font-mono text-xs">{category.code}</Badge>
        )}
        <span className="shrink-0 font-mono text-xs text-muted-foreground">
          {category.parts_count} part{category.parts_count !== 1 ? 's' : ''}
        </span>
        {canWrite && (
          <div className="flex shrink-0 items-center gap-1">
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label="Add subcategory"
              onClick={() => openNewDialog(category.id)}
            >
              <Plus className="size-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label="Edit category"
              onClick={() => openEditDialog(category)}
            >
              <Pencil className="size-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label="Delete category"
              className="text-destructive"
              onClick={() => openDeleteDialog(category.id)}
            >
              <Trash2 className="size-4" />
            </Button>
          </div>
        )}
      </div>,
      ...renderRows(category.id, depth + 1),
    ])

  return (
    <AppLayout
      header={
        <PageHeader title="Categories" subtitle="Organize your components into a hierarchy">
          {canWrite && (
            <Button size="sm" onClick={() => openNewDialog()}>
              <Plus className="size-4" />
              Add Category
            </Button>
          )}
        </PageHeader>
      }
    >
      <Head title="Categories" />

      <div className="space-y-6">
        <FlashMessages />

        {/* Stats */}
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          {stats.map((stat) => (
            <Card key={stat.label}>
              <CardContent className="flex items-center justify-between">
                <div>
                  <div className="text-sm text-muted-foreground">{stat.label}</div>
                  <div className="mt-1 font-mono text-2xl font-bold">{stat.value}</div>
                </div>
                <FolderTree className="size-5 text-muted-foreground" />
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Category tree */}
        {categories.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
              <FolderTree className="size-8 text-muted-foreground" />
              <div>
                <p className="font-medium">No categories yet</p>
                <p className="text-sm text-muted-foreground">
                  {canWrite
                    ? 'Add your first category so parts can be classified.'
                    : 'No categories have been added yet.'}
                </p>
              </div>
              {canWrite && (
                <Button onClick={() => openNewDialog()}>
                  <Plus className="size-4" />
                  Add Category
                </Button>
              )}
            </CardContent>
          </Card>
        ) : (
          <Card className="gap-0 overflow-hidden py-0">{renderRows(null, 0)}</Card>
        )}
      </div>

      {/* New category dialog */}
      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add category</DialogTitle>
          </DialogHeader>
          <CategoryForm
            data={newForm.data.category}
            errors={categoryErrors(newForm.errors)}
            parentOptions={parentOptions}
            onChange={(patch) => newForm.setData('category', { ...newForm.data.category, ...patch })}
            onSubmit={submitNew}
            onCancel={() => setNewOpen(false)}
            processing={newForm.processing}
            submitLabel="Add category"
          />
        </DialogContent>
      </Dialog>

      {/* Edit category dialog */}
      <Dialog open={editId != null} onOpenChange={(open) => !open && setEditId(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit category</DialogTitle>
          </DialogHeader>
          <CategoryForm
            data={editForm.data.category}
            errors={categoryErrors(editForm.errors)}
            parentOptions={parentOptions}
            onChange={(patch) => editForm.setData('category', { ...editForm.data.category, ...patch })}
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
            <AlertDialogTitle>Delete this category?</AlertDialogTitle>
            <AlertDialogDescription>
              <span className="font-semibold text-foreground">{deleting?.name}</span> will be removed.
              {deleting && childCount(deleting.id) > 0 && (
                <> Its {childCount(deleting.id)} subcategor{childCount(deleting.id) !== 1 ? 'ies' : 'y'} will be deleted too.</>
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>

          {deletingPartsCount > 0 && (
            <div className="space-y-2">
              <Label>
                Move {deletingPartsCount} part{deletingPartsCount !== 1 ? 's' : ''} to
              </Label>
              {deleteTargetOptions.length > 0 ? (
                <Select value={reassignTarget} onValueChange={setReassignTarget}>
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder="Select a destination category" />
                  </SelectTrigger>
                  <SelectContent>
                    {deleteTargetOptions.map((option) => (
                      <SelectItem key={option.id} value={String(option.id)}>{option.label}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <p className="text-sm text-destructive">
                  Create another category first so these parts have somewhere to go.
                </p>
              )}
            </div>
          )}

          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={confirmDelete}
              disabled={deletingPartsCount > 0 && !reassignTarget}
              className="bg-destructive text-white hover:bg-destructive/90"
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </AppLayout>
  )
}

// The server reports parent errors on `:parent` / `:parent_id`, which aren't
// both form fields, so read the flattened error bag loosely.
function categoryErrors(errors: Partial<Record<string, string | string[]>>) {
  return {
    name: errors['category.name'],
    code: errors['category.code'],
    parent: errors['category.parent'] ?? errors['category.parent_id'],
  }
}

// Convert the sentinel "none" parent back to an empty value the server reads as nil.
function normalize(data: CategoryFormData): CategoryFormData {
  return {
    category: {
      ...data.category,
      parent_id: data.category.parent_id === NONE_VALUE ? '' : data.category.parent_id,
    },
  }
}

interface CategoryFormProps {
  data: CategoryFormData['category']
  errors: {
    name?: string | string[]
    code?: string | string[]
    parent?: string | string[]
  }
  parentOptions: Array<{ id: number; label: string }>
  onChange: (patch: Partial<CategoryFormData['category']>) => void
  onSubmit: (e: FormEvent) => void
  onCancel: () => void
  processing: boolean
  submitLabel: string
}

function CategoryForm({
  data, errors, parentOptions, onChange, onSubmit, onCancel, processing, submitLabel,
}: CategoryFormProps) {
  return (
    <form onSubmit={onSubmit} className="flex flex-col gap-4">
      <div className="grid grid-cols-3 gap-4">
        <Field className="col-span-2">
          <FieldLabel>
            <Label>Name</Label>
          </FieldLabel>
          <FieldContent>
            <Input
              placeholder="e.g. Resistors"
              value={data.name}
              onChange={(e) => onChange({ name: e.target.value })}
            />
          </FieldContent>
          {errors.name && <FieldError>{errors.name}</FieldError>}
        </Field>
        <Field>
          <FieldLabel>
            <Label>Code</Label>
          </FieldLabel>
          <FieldContent>
            <Input
              placeholder="RES"
              value={data.code}
              onChange={(e) => onChange({ code: e.target.value })}
            />
          </FieldContent>
          {errors.code && <FieldError>{errors.code}</FieldError>}
        </Field>
      </div>

      <Field>
        <FieldLabel>
          <Label>Parent category</Label>
        </FieldLabel>
        <FieldContent>
          <Select
            value={data.parent_id || NONE_VALUE}
            onValueChange={(value) => onChange({ parent_id: value === NONE_VALUE ? '' : value })}
          >
            <SelectTrigger className="w-full">
              <SelectValue placeholder="No parent (top-level)" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={NONE_VALUE}>No parent (top-level)</SelectItem>
              {parentOptions.map((option) => (
                <SelectItem key={option.id} value={String(option.id)}>{option.label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </FieldContent>
        {errors.parent && <FieldError>{errors.parent}</FieldError>}
      </Field>

      <Field>
        <FieldLabel>
          <Label>Color</Label>
        </FieldLabel>
        <FieldContent>
          <div className="flex flex-wrap gap-2">
            {PRESET_COLORS.map((preset) => (
              <button
                key={preset.value ?? 'none'}
                type="button"
                onClick={() => onChange({ color: preset.value ?? '' })}
                aria-label={preset.value ?? 'No color'}
                className={`size-6 rounded-full border ${preset.className} ${
                  (data.color || '') === (preset.value ?? '')
                    ? 'ring-2 ring-ring ring-offset-2 ring-offset-background'
                    : ''
                }`}
              />
            ))}
          </div>
        </FieldContent>
      </Field>

      <Field>
        <FieldLabel>
          <Label>Description</Label>
        </FieldLabel>
        <FieldContent>
          <Textarea
            placeholder="Optional notes about this category"
            value={data.description}
            onChange={(e) => onChange({ description: e.target.value })}
          />
        </FieldContent>
      </Field>

      <DialogFooter>
        <Button type="button" variant="outline" onClick={onCancel}>Cancel</Button>
        <Button type="submit" disabled={processing}>{submitLabel}</Button>
      </DialogFooter>
    </form>
  )
}
