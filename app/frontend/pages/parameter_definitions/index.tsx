import { Head, router, useForm } from '@inertiajs/react'
import { FormEvent, useMemo, useState } from 'react'
import { Plus, SlidersHorizontal, Pencil, Trash2, Sparkles } from 'lucide-react'

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
import { Field, FieldContent, FieldDescription, FieldError, FieldLabel } from '@/components/ui/field'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
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
import { t, tn, tx } from '@/lib/i18n'

interface ParameterDefinition {
  id: number
  name: string
  value_type: 'number' | 'text'
  unit: string | null
  description: string | null
  parts_count: number
  category_names: string[]
}

interface ParametersPageProps {
  definitions: ParameterDefinition[]
  // How many of the standard parameters the organization doesn't have yet.
  standard_missing: number
}

interface DefinitionFormData {
  parameter_definition: {
    name: string
    value_type: 'number' | 'text'
    unit: string
    description: string
  }
}

const EMPTY_FORM: DefinitionFormData['parameter_definition'] = {
  name: '', value_type: 'number', unit: '', description: '',
}

export default function ParameterDefinitionsIndex({ definitions, standard_missing }: ParametersPageProps) {
  const { canWrite } = usePermissions()
  const [newOpen, setNewOpen] = useState(false)
  const [editId, setEditId] = useState<number | null>(null)
  const [deleteId, setDeleteId] = useState<number | null>(null)
  const [installing, setInstalling] = useState(false)

  const editing = editId != null ? definitions.find((d) => d.id === editId) : undefined
  const deleting = deleteId != null ? definitions.find((d) => d.id === deleteId) : undefined

  const newForm = useForm<DefinitionFormData>({ parameter_definition: EMPTY_FORM })
  const editForm = useForm<DefinitionFormData>({ parameter_definition: EMPTY_FORM })

  const stats = useMemo(() => [
    { label: t('Parameters'), value: String(definitions.length) },
    { label: t('In category templates'), value: String(definitions.filter((d) => d.category_names.length > 0).length) },
    { label: t('Part values'), value: String(definitions.reduce((sum, d) => sum + d.parts_count, 0)) },
  ], [definitions])

  const openNewDialog = () => {
    newForm.reset()
    newForm.clearErrors()
    setNewOpen(true)
  }

  const submitNew = (e: FormEvent) => {
    e.preventDefault()
    newForm.post('/parameters', { preserveScroll: true, onSuccess: () => setNewOpen(false) })
  }

  const openEditDialog = (definition: ParameterDefinition) => {
    editForm.clearErrors()
    editForm.setData('parameter_definition', {
      name: definition.name,
      value_type: definition.value_type,
      unit: definition.unit || '',
      description: definition.description || '',
    })
    setEditId(definition.id)
  }

  const submitEdit = (e: FormEvent) => {
    e.preventDefault()
    if (!editing) return
    editForm.patch(`/parameters/${editing.id}`, { preserveScroll: true, onSuccess: () => setEditId(null) })
  }

  const confirmDelete = () => {
    if (!deleting) return
    router.delete(`/parameters/${deleting.id}`, { preserveScroll: true, onSuccess: () => setDeleteId(null) })
  }

  const installStandard = () => {
    router.post('/parameters/standard', {}, {
      preserveScroll: true,
      onStart: () => setInstalling(true),
      onFinish: () => setInstalling(false),
    })
  }

  const standardButton = canWrite && standard_missing > 0 && (
    <Button size="sm" variant="outline" onClick={installStandard} disabled={installing}>
      <Sparkles className="size-4" />
      {t('Add standard parameters')}
    </Button>
  )

  return (
    <AppLayout
      header={
        <PageHeader title={t('Parameters')} subtitle={t('Technical values parts are filtered on: resistance, capacitance, tolerance…')}>
          {definitions.length > 0 && standardButton}
          {canWrite && (
            <Button size="sm" onClick={openNewDialog}>
              <Plus className="size-4" />
              {t('Add Parameter')}
            </Button>
          )}
        </PageHeader>
      }
    >
      <Head title={t('Parameters')} />

      <div className="space-y-6">
        <FlashMessages />

        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3">
          {stats.map((stat) => (
            <Card key={stat.label}>
              <CardContent className="flex items-center justify-between">
                <div>
                  <div className="text-sm text-muted-foreground">{stat.label}</div>
                  <div className="mt-1 font-mono text-2xl font-bold">{stat.value}</div>
                </div>
                <SlidersHorizontal className="size-5 text-muted-foreground" />
              </CardContent>
            </Card>
          ))}
        </div>

        {definitions.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
              <SlidersHorizontal className="size-8 text-muted-foreground" />
              <div>
                <p className="font-medium">{t('No parameters yet')}</p>
                <p className="max-w-md text-sm text-muted-foreground">
                  {canWrite
                    ? t('Start from the standard set (resistance, capacitance, inductance, tolerance, voltage, power, current, frequency, dielectric, color): resistor, capacitor, inductor, crystal and LED categories get their template, and existing parts are filled in from their Value, Tolerance, Voltage and Power fields.')
                    : t('No parameters have been defined yet.')}
                </p>
              </div>
              {canWrite && (
                <div className="flex flex-wrap justify-center gap-2">
                  {standardButton}
                  <Button variant="outline" size="sm" onClick={openNewDialog}>
                    <Plus className="size-4" />
                    {t('Add Parameter')}
                  </Button>
                </div>
              )}
            </CardContent>
          </Card>
        ) : (
          <Card className="overflow-hidden py-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t('Name')}</TableHead>
                  <TableHead>{t('Type')}</TableHead>
                  <TableHead>{t('Proposed for')}</TableHead>
                  <TableHead className="text-right">{t('Parts')}</TableHead>
                  {canWrite && <TableHead className="w-24" />}
                </TableRow>
              </TableHeader>
              <TableBody>
                {definitions.map((definition) => (
                  <TableRow key={definition.id}>
                    <TableCell>
                      <div className="font-medium">{definition.name}</div>
                      {definition.description && (
                        <div className="max-w-xs truncate text-xs text-muted-foreground">{definition.description}</div>
                      )}
                    </TableCell>
                    <TableCell>
                      {definition.value_type === 'number' ? (
                        <Badge variant="outline" className="font-mono">{definition.unit ? t('Number · {unit}', { unit: definition.unit }) : t('Number')}</Badge>
                      ) : (
                        <Badge variant="secondary">{t('Text')}</Badge>
                      )}
                    </TableCell>
                    <TableCell className="max-w-sm text-sm text-muted-foreground">
                      {definition.category_names.length > 0 ? definition.category_names.join(', ') : '-'}
                    </TableCell>
                    <TableCell className="text-right font-mono">{definition.parts_count}</TableCell>
                    {canWrite && (
                      <TableCell>
                        <div className="flex items-center justify-end gap-1">
                          <Button variant="ghost" size="icon-sm" aria-label={t('Edit parameter')} onClick={() => openEditDialog(definition)}>
                            <Pencil className="size-4" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon-sm"
                            aria-label={t('Delete parameter')}
                            className="text-destructive"
                            onClick={() => setDeleteId(definition.id)}
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
        {definitions.length > 0 && (
          <p className="text-sm text-muted-foreground">
            {t('Choose which parameters a category proposes when editing the category (Categories page); sub-categories inherit them.')}
          </p>
        )}
      </div>

      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('Add parameter')}</DialogTitle>
          </DialogHeader>
          <DefinitionForm
            data={newForm.data.parameter_definition}
            errors={newForm.errors as Record<string, string>}
            onChange={(patch) => newForm.setData('parameter_definition', { ...newForm.data.parameter_definition, ...patch })}
            onSubmit={submitNew}
            onCancel={() => setNewOpen(false)}
            processing={newForm.processing}
            submitLabel={t('Add parameter')}
          />
        </DialogContent>
      </Dialog>

      <Dialog open={editId != null} onOpenChange={(open) => !open && setEditId(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('Edit parameter')}</DialogTitle>
          </DialogHeader>
          <DefinitionForm
            data={editForm.data.parameter_definition}
            errors={editForm.errors as Record<string, string>}
            onChange={(patch) => editForm.setData('parameter_definition', { ...editForm.data.parameter_definition, ...patch })}
            onSubmit={submitEdit}
            onCancel={() => setEditId(null)}
            processing={editForm.processing}
            submitLabel={t('Save')}
          />
        </DialogContent>
      </Dialog>

      <AlertDialog open={deleteId != null} onOpenChange={(open) => !open && setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('Delete this parameter?')}</AlertDialogTitle>
            <AlertDialogDescription>
              {tx('{name} will be removed from every category template.', { name: <span className="font-semibold text-foreground">{deleting?.name}</span> })}
              {deleting && deleting.parts_count > 0 && (
                <>{' '}{tn('Its value on {count} part is deleted too; the part itself is kept.', 'Its value on {count} parts is deleted too; the parts themselves are kept.', deleting.parts_count)}</>
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('Cancel')}</AlertDialogCancel>
            <AlertDialogAction onClick={confirmDelete} className="bg-destructive text-white hover:bg-destructive/90">
              {t('Delete')}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </AppLayout>
  )
}

interface DefinitionFormProps {
  data: DefinitionFormData['parameter_definition']
  errors: Record<string, string>
  onChange: (patch: Partial<DefinitionFormData['parameter_definition']>) => void
  onSubmit: (e: FormEvent) => void
  onCancel: () => void
  processing: boolean
  submitLabel: string
}

function DefinitionForm({ data, errors, onChange, onSubmit, onCancel, processing, submitLabel }: DefinitionFormProps) {
  return (
    <form onSubmit={onSubmit} className="flex flex-col gap-4">
      {errors['parameter_definition.base'] && <FieldError>{errors['parameter_definition.base']}</FieldError>}
      <Field>
        <FieldLabel>
          <Label htmlFor="parameter-name">{t('Name')}</Label>
        </FieldLabel>
        <FieldContent>
          <Input id="parameter-name" placeholder={t('e.g. Forward voltage')} value={data.name} onChange={(e) => onChange({ name: e.target.value })} />
        </FieldContent>
        {errors['parameter_definition.name'] && <FieldError>{errors['parameter_definition.name']}</FieldError>}
      </Field>

      <div className="grid grid-cols-2 gap-4">
        <Field>
          <FieldLabel>
            <Label>{t('Type')}</Label>
          </FieldLabel>
          <FieldContent>
            <Select value={data.value_type} onValueChange={(value) => onChange({ value_type: value as 'number' | 'text' })}>
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="number">{t('Number (range filters)')}</SelectItem>
                <SelectItem value="text">{t('Text (value list)')}</SelectItem>
              </SelectContent>
            </Select>
          </FieldContent>
        </Field>
        {data.value_type === 'number' && (
          <Field>
            <FieldLabel>
              <Label htmlFor="parameter-unit">{t('Unit')}</Label>
            </FieldLabel>
            <FieldContent>
              <Input id="parameter-unit" placeholder="e.g. V, Ω, F, %" value={data.unit} onChange={(e) => onChange({ unit: e.target.value })} />
            </FieldContent>
            {errors['parameter_definition.unit'] && <FieldError>{errors['parameter_definition.unit']}</FieldError>}
          </Field>
        )}
      </div>
      {data.value_type === 'number' && (
        <FieldDescription>
          {t('Values are typed as usual (4k7, 100nF, 1/4W, 3V3) and stored in the unit, so they can be filtered by range.')}
        </FieldDescription>
      )}

      <Field>
        <FieldLabel>
          <Label>{t('Description')}</Label>
        </FieldLabel>
        <FieldContent>
          <Textarea placeholder={t('Optional')} value={data.description} onChange={(e) => onChange({ description: e.target.value })} />
        </FieldContent>
      </Field>

      <DialogFooter>
        <Button type="button" variant="outline" onClick={onCancel}>{t('Cancel')}</Button>
        <Button type="submit" disabled={processing}>{submitLabel}</Button>
      </DialogFooter>
    </form>
  )
}
