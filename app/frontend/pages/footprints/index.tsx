import { Head, router, useForm } from '@inertiajs/react'
import { FormEvent, useMemo, useState } from 'react'
import { Plus, Cpu, Pencil, Trash2 } from 'lucide-react'

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
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
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

const MOUNTING_TYPE_META: Record<string, string> = {
  SMD: 'bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-400',
  'Through-hole': 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400',
  Both: 'bg-purple-100 text-purple-700 dark:bg-purple-950 dark:text-purple-400',
}

const NONE_VALUE = '__none__'

interface Footprint {
  id: number
  name: string
  description: string | null
  mounting_type: string | null
  parts_count: number
}

interface FootprintsPageProps {
  footprints: Footprint[]
  mounting_types: string[]
}

interface FootprintFormData {
  footprint: {
    name: string
    description: string
    mounting_type: string
  }
}

const EMPTY_FORM: FootprintFormData['footprint'] = {
  name: '', description: '', mounting_type: '',
}

export default function FootprintsIndex({ footprints, mounting_types }: FootprintsPageProps) {
  const { canWrite } = usePermissions()
  const [newOpen, setNewOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [deleteId, setDeleteId] = useState<number | null>(null)

  const editing = editId != null ? footprints.find((f) => f.id === editId) : undefined
  const deleting = deleteId != null ? footprints.find((f) => f.id === deleteId) : undefined

  const newForm = useForm<FootprintFormData>({ footprint: EMPTY_FORM })
  const editForm = useForm<FootprintFormData>({ footprint: EMPTY_FORM })

  const stats = useMemo(() => {
    const withParts = footprints.filter((f) => f.parts_count > 0).length
    const smd = footprints.filter((f) => f.mounting_type === 'SMD').length
    const tht = footprints.filter((f) => f.mounting_type === 'Through-hole').length
    return [
      { label: 'Footprints', value: String(footprints.length) },
      { label: 'In use', value: String(withParts) },
      { label: 'SMD', value: String(smd) },
      { label: 'Through-hole', value: String(tht) },
    ]
  }, [footprints])

  const openNewDialog = () => {
    newForm.reset()
    newForm.clearErrors()
    setNewOpen(true)
  }

  const submitNew = (e: FormEvent) => {
    e.preventDefault()
    newForm.post('/footprints', {
      preserveScroll: true,
      onSuccess: () => setNewOpen(false),
    })
  }

  const openEditDialog = (footprint: Footprint) => {
    editForm.clearErrors()
    editForm.setData('footprint', {
      name: footprint.name,
      description: footprint.description || '',
      mounting_type: footprint.mounting_type || '',
    })
    setEditId(footprint.id)
  }

  const submitEdit = (e: FormEvent) => {
    e.preventDefault()
    if (!editing) return
    editForm.patch(`/footprints/${editing.id}`, {
      preserveScroll: true,
      onSuccess: () => setEditId(null),
    })
  }

  const confirmDelete = () => {
    if (!deleting) return
    router.delete(`/footprints/${deleting.id}`, {
      preserveScroll: true,
      onSuccess: () => setDeleteId(null),
    })
  }

  return (
    <AppLayout
      header={
        <PageHeader title="Footprints" subtitle="Component packages and mounting types">
          {canWrite && (
            <Button size="sm" onClick={openNewDialog}>
              <Plus className="size-4" />
              Add Footprint
            </Button>
          )}
        </PageHeader>
      }
    >
      <Head title="Footprints" />

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
                <Cpu className="size-5 text-muted-foreground" />
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Footprint table */}
        {footprints.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
              <Cpu className="size-8 text-muted-foreground" />
              <div>
                <p className="font-medium">No footprints yet</p>
                <p className="text-sm text-muted-foreground">
                  {canWrite
                    ? 'Add your first footprint to describe component packages.'
                    : 'No footprints have been added yet.'}
                </p>
              </div>
              {canWrite && (
                <Button onClick={openNewDialog}>
                  <Plus className="size-4" />
                  Add Footprint
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
                  <TableHead>Mounting</TableHead>
                  <TableHead>Description</TableHead>
                  <TableHead className="text-right">Parts</TableHead>
                  {canWrite && <TableHead className="w-24" />}
                </TableRow>
              </TableHeader>
              <TableBody>
                {footprints.map((footprint) => (
                  <TableRow key={footprint.id}>
                    <TableCell className="font-medium">{footprint.name}</TableCell>
                    <TableCell>
                      {footprint.mounting_type ? (
                        <Badge variant="outline" className={MOUNTING_TYPE_META[footprint.mounting_type]}>
                          {footprint.mounting_type}
                        </Badge>
                      ) : (
                        <span className="text-muted-foreground">-</span>
                      )}
                    </TableCell>
                    <TableCell className="max-w-xs truncate text-muted-foreground">
                      {footprint.description || '-'}
                    </TableCell>
                    <TableCell className="text-right font-mono">{footprint.parts_count}</TableCell>
                    {canWrite && (
                      <TableCell>
                        <div className="flex items-center justify-end gap-1">
                          <Button
                            variant="ghost"
                            size="icon-sm"
                            aria-label="Edit footprint"
                            onClick={() => openEditDialog(footprint)}
                          >
                            <Pencil className="size-4" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon-sm"
                            aria-label="Delete footprint"
                            className="text-destructive"
                            onClick={() => setDeleteId(footprint.id)}
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

      {/* New footprint dialog */}
      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add footprint</DialogTitle>
          </DialogHeader>
          <FootprintForm
            data={newForm.data.footprint}
            errors={{
              name: newForm.errors['footprint.name'],
              mounting_type: newForm.errors['footprint.mounting_type'],
              description: newForm.errors['footprint.description'],
            }}
            mountingTypes={mounting_types}
            onChange={(patch) => newForm.setData('footprint', { ...newForm.data.footprint, ...patch })}
            onSubmit={submitNew}
            onCancel={() => setNewOpen(false)}
            processing={newForm.processing}
            submitLabel="Add footprint"
          />
        </DialogContent>
      </Dialog>

      {/* Edit footprint dialog */}
      <Dialog open={editId != null} onOpenChange={(open) => !open && setEditId(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit footprint</DialogTitle>
          </DialogHeader>
          <FootprintForm
            data={editForm.data.footprint}
            errors={{
              name: editForm.errors['footprint.name'],
              mounting_type: editForm.errors['footprint.mounting_type'],
              description: editForm.errors['footprint.description'],
            }}
            mountingTypes={mounting_types}
            onChange={(patch) => editForm.setData('footprint', { ...editForm.data.footprint, ...patch })}
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
            <AlertDialogTitle>Delete this footprint?</AlertDialogTitle>
            <AlertDialogDescription>
              <span className="font-semibold text-foreground">{deleting?.name}</span> will be removed.
              {deleting && deleting.parts_count > 0 && (
                <> This footprint is used by {deleting.parts_count} part{deleting.parts_count !== 1 ? 's' : ''} and cannot be deleted while in use.</>
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

interface FootprintFormProps {
  data: FootprintFormData['footprint']
  errors: {
    name?: string | string[]
    mounting_type?: string | string[]
    description?: string | string[]
  }
  mountingTypes: string[]
  onChange: (patch: Partial<FootprintFormData['footprint']>) => void
  onSubmit: (e: FormEvent) => void
  onCancel: () => void
  processing: boolean
  submitLabel: string
}

function FootprintForm({
  data, errors, mountingTypes, onChange, onSubmit, onCancel, processing, submitLabel,
}: FootprintFormProps) {
  return (
    <form onSubmit={onSubmit} className="flex flex-col gap-4">
      <Field>
        <FieldLabel>
          <Label>Name</Label>
        </FieldLabel>
        <FieldContent>
          <Input
            placeholder="e.g. 0805, SOT-23, DIP-8"
            value={data.name}
            onChange={(e) => onChange({ name: e.target.value })}
          />
        </FieldContent>
        {errors.name && <FieldError>{errors.name}</FieldError>}
      </Field>
      <Field>
        <FieldLabel>
          <Label>Mounting type</Label>
        </FieldLabel>
        <FieldContent>
          <Select
            value={data.mounting_type || NONE_VALUE}
            onValueChange={(value) => onChange({ mounting_type: value === NONE_VALUE ? '' : value })}
          >
            <SelectTrigger className="w-full">
              <SelectValue placeholder="Select a mounting type" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={NONE_VALUE}>None</SelectItem>
              {mountingTypes.map((type) => (
                <SelectItem key={type} value={type}>{type}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </FieldContent>
        {errors.mounting_type && <FieldError>{errors.mounting_type}</FieldError>}
      </Field>
      <Field>
        <FieldLabel>
          <Label>Description</Label>
        </FieldLabel>
        <FieldContent>
          <Textarea
            placeholder="Optional notes about this package"
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
