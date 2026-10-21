import { Head, Link, router } from '@inertiajs/react'
import { FormEvent, useMemo, useState } from 'react'
import {
  ArrowLeft,
  CheckCircle2,
  AlertTriangle,
  XCircle,
  FileText,
  Hammer,
  Lock,
  LockOpen,
  Plus,
  Pencil,
  Copy,
  Trash2,
  History,
} from 'lucide-react'

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
import { Combobox, type ComboboxOption } from '@/components/ui/combobox'
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
  DialogDescription,
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

interface LinePart {
  id: number
  reference: string
  name: string
}

interface ProjectLine {
  id: number
  raw_reference: string | null
  designation: string | null
  value: string | null
  footprint: string | null
  designators: string | null
  quantity: number
  match_type: 'mpn' | 'sku' | 'supplier_sku' | 'value_footprint' | 'name' | 'manual' | 'none'
  in_stock: number
  reserved_elsewhere: number
  shortfall: number
  available: boolean
  part: LinePart | null
}

interface ProjectBuild {
  id: number
  quantity: number
  built_at: string
  note: string | null
  user: string | null
  references: number
  units: number
}

interface Project {
  id: number
  name: string
  description: string | null
  reference: string | null
  revision: string | null
  next_revision: string
  status: 'draft' | 'confirmed'
  reservations_enabled: boolean
  reserved: boolean
  reserved_at: string | null
  buildable: boolean
  short_count: number
  unmatched_count: number
  checked_at: string | null
  builds_count: number
  last_built_at: string | null
  builds: ProjectBuild[]
  lines: ProjectLine[]
}

interface PartOption {
  id: number
  reference: string
  name: string
  mpn: string | null
  sku: string | null
}

interface ProjectShowProps {
  project: Project
  parts: PartOption[]
}

const NONE = '__none__'

const MATCH_LABELS: Record<ProjectLine['match_type'], string> = {
  mpn: 'by MPN',
  sku: 'by SKU',
  supplier_sku: 'by supplier SKU',
  value_footprint: 'by value + footprint',
  name: 'by name',
  manual: 'manual',
  none: 'no match',
}

export default function ProjectShow({ project, parts }: ProjectShowProps) {
  const { canWrite } = usePermissions()
  const [buildOpen, setBuildOpen] = useState(false)
  const [kits, setKits] = useState('1')
  const [buildNote, setBuildNote] = useState('')
  const [editOpen, setEditOpen] = useState(false)
  const [revisionOpen, setRevisionOpen] = useState(false)
  const [lineOpen, setLineOpen] = useState(false)
  const [removeLine, setRemoveLine] = useState<ProjectLine | null>(null)

  const partOptions = useMemo<ComboboxOption[]>(
    () => [
      { value: NONE, label: 'Not in inventory' },
      ...parts.map((p) => ({ value: String(p.id), label: `${p.reference} — ${p.name}` })),
    ],
    [parts]
  )

  const matchedCount = project.lines.filter((l) => l.part).length

  const updateLine = (line: ProjectLine, data: Record<string, string | number>) => {
    router.patch(`/projects/${project.id}/project_lines/${line.id}`, { project_line: data }, { preserveScroll: true })
  }

  const changePart = (line: ProjectLine, value: string) => {
    updateLine(line, { part_id: value === NONE ? '' : value })
  }

  const changeQuantity = (line: ProjectLine, raw: string) => {
    const quantity = Number(raw)
    if (!Number.isInteger(quantity) || quantity < 1 || quantity === line.quantity) return
    updateLine(line, { quantity })
  }

  const kitCount = Number(kits)
  const kitsValid = Number.isInteger(kitCount) && kitCount >= 1

  const build = () => {
    router.post(
      `/projects/${project.id}/build`,
      { builds_count: project.builds_count, kits: kitCount, note: buildNote.trim() },
      { preserveScroll: true, onSuccess: () => { setKits('1'); setBuildNote('') } }
    )
    setBuildOpen(false)
  }

  const subtitle = [project.reference, project.revision ? `rev ${project.revision}` : null].filter(Boolean).join(' · ')

  return (
    <AppLayout
      header={
        <PageHeader title={project.name} subtitle={subtitle || undefined}>
          {canWrite && (
            <div className="flex flex-wrap gap-2">
              <Button size="sm" variant="outline" onClick={() => setEditOpen(true)}>
                <Pencil className="size-4" />
                Edit
              </Button>
              <Button size="sm" variant="outline" onClick={() => setRevisionOpen(true)}>
                <Copy className="size-4" />
                New revision
              </Button>
              {project.status === 'draft' && (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => router.post(`/projects/${project.id}/confirm`, {}, { preserveScroll: true })}
                >
                  <CheckCircle2 className="size-4" />
                  Confirm matches
                </Button>
              )}
              {project.status === 'confirmed' && project.reservations_enabled && (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => router.post(`/projects/${project.id}/${project.reserved ? 'release' : 'reserve'}`, {}, { preserveScroll: true })}
                >
                  {project.reserved ? <LockOpen className="size-4" /> : <Lock className="size-4" />}
                  {project.reserved ? 'Release stock' : 'Reserve stock'}
                </Button>
              )}
              <Button
                size="sm"
                variant="outline"
                disabled={project.short_count === 0}
                title={project.short_count === 0 ? 'No shortfalls to order' : undefined}
                onClick={() => router.post(`/projects/${project.id}/create_purchase_orders`, {}, { preserveScroll: true })}
              >
                <FileText className="size-4" />
                Order shortfalls
              </Button>
              <Button
                size="sm"
                disabled={!project.buildable}
                title={project.buildable ? undefined : 'Resolve shortfalls and unmatched lines first'}
                onClick={() => setBuildOpen(true)}
              >
                <Hammer className="size-4" />
                Build
              </Button>
            </div>
          )}
        </PageHeader>
      }
    >
      <Head title={project.name} />

      <div className="space-y-6">
        <FlashMessages />

        <Link href="/projects" className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground">
          <ArrowLeft className="size-4" />
          All projects
        </Link>

        {project.description && <p className="max-w-3xl text-sm text-muted-foreground">{project.description}</p>}

        {/* Availability summary */}
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <SummaryCard label="Total lines" value={project.lines.length} />
          <SummaryCard label="Matched" value={`${matchedCount} / ${project.lines.length}`} />
          <SummaryCard label="Short on stock" value={project.short_count} tone={project.short_count > 0 ? 'amber' : undefined} />
          <SummaryCard label="Not in inventory" value={project.unmatched_count} tone={project.unmatched_count > 0 ? 'red' : undefined} />
        </div>

        <Card className={`border-l-[3px] ${project.buildable ? 'border-l-emerald-500' : 'border-l-amber-500'}`}>
          <CardContent className="flex items-center gap-3">
            {project.buildable ? (
              <>
                <CheckCircle2 className="size-5 text-emerald-600 dark:text-emerald-400" />
                <p className="text-sm font-medium">You have enough stock to build this project.</p>
              </>
            ) : project.lines.length === 0 ? (
              <>
                <AlertTriangle className="size-5 text-amber-600 dark:text-amber-400" />
                <p className="text-sm font-medium">This project has no lines yet: add the parts it needs to see what you can build.</p>
              </>
            ) : (
              <>
                <AlertTriangle className="size-5 text-amber-600 dark:text-amber-400" />
                <p className="text-sm font-medium">
                  {project.short_count + project.unmatched_count} line{project.short_count + project.unmatched_count !== 1 ? 's' : ''} need resolving before this project is buildable.
                </p>
              </>
            )}
            {project.reserved && project.reserved_at && (
              <Badge variant="outline" className="ml-auto">
                <Lock className="size-3.5" /> Stock reserved since {new Date(project.reserved_at).toLocaleDateString()}
              </Badge>
            )}
            {project.builds_count > 0 && project.last_built_at && (
              <p className={`${project.reserved ? '' : 'ml-auto '}text-xs text-muted-foreground`}>
                {project.builds_count} kit{project.builds_count !== 1 ? 's' : ''} built · last on {new Date(project.last_built_at).toLocaleDateString()}
              </p>
            )}
          </CardContent>
        </Card>

        {/* BOM lines */}
        <Card className="overflow-hidden py-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>BOM reference</TableHead>
                <TableHead>Matched part</TableHead>
                <TableHead className="text-right">Required</TableHead>
                <TableHead className="text-right">In stock</TableHead>
                {project.reservations_enabled && (
                  <TableHead className="text-right" title="Held by projects reserved before this one">Reserved elsewhere</TableHead>
                )}
                <TableHead>Status</TableHead>
                {canWrite && <TableHead className="w-10" />}
              </TableRow>
            </TableHeader>
            <TableBody>
              {project.lines.length === 0 && (
                <TableRow>
                  <TableCell colSpan={7} className="py-8 text-center text-sm text-muted-foreground">
                    No lines yet.{canWrite && ' Add the parts this project needs.'}
                  </TableCell>
                </TableRow>
              )}
              {project.lines.map((line) => (
                <TableRow key={line.id}>
                  <TableCell>
                    <div className="font-mono text-sm font-medium">{line.raw_reference || '—'}</div>
                    <div className="max-w-[220px] truncate text-xs text-muted-foreground">{line.designation}</div>
                    {(line.footprint || (line.value && line.value !== line.designation)) && (
                      <div className="max-w-[220px] truncate text-xs text-muted-foreground" title={line.footprint ?? undefined}>
                        {[line.value !== line.designation ? line.value : null, line.footprint?.split(':').pop()]
                          .filter(Boolean)
                          .join(' · ')}
                      </div>
                    )}
                    {line.designators && (
                      <div className="max-w-[220px] truncate font-mono text-xs text-muted-foreground" title={line.designators}>
                        {line.designators}
                      </div>
                    )}
                  </TableCell>
                  <TableCell>
                    {canWrite ? (
                      <div className="flex items-center gap-2">
                        <Combobox
                          options={partOptions}
                          value={line.part ? String(line.part.id) : NONE}
                          onValueChange={(value) => changePart(line, value)}
                          placeholder="Not in inventory"
                          searchPlaceholder="Search parts…"
                          className="min-w-[220px]"
                        />
                        <span className="text-xs text-muted-foreground">{MATCH_LABELS[line.match_type]}</span>
                      </div>
                    ) : line.part ? (
                      <span>{line.part.reference} — {line.part.name}</span>
                    ) : (
                      <span className="text-muted-foreground">Not in inventory</span>
                    )}
                  </TableCell>
                  <TableCell className="text-right">
                    {canWrite ? (
                      <Input
                        type="number"
                        min={1}
                        defaultValue={line.quantity}
                        className="ml-auto h-8 w-20 text-right font-mono"
                        onBlur={(e) => changeQuantity(line, e.target.value)}
                      />
                    ) : (
                      <span className="font-mono">{line.quantity}</span>
                    )}
                  </TableCell>
                  <TableCell className="text-right font-mono">{line.part ? line.in_stock : '—'}</TableCell>
                  {project.reservations_enabled && (
                    <TableCell className="text-right font-mono text-muted-foreground">
                      {line.part && line.reserved_elsewhere > 0 ? line.reserved_elsewhere : '—'}
                    </TableCell>
                  )}
                  <TableCell>
                    {!line.part ? (
                      <Badge variant="outline" className="bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400">
                        <XCircle className="size-3.5" /> Not in inventory
                      </Badge>
                    ) : line.available ? (
                      <Badge variant="outline" className="bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400">
                        <CheckCircle2 className="size-3.5" /> OK
                      </Badge>
                    ) : (
                      <Badge variant="outline" className="bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400">
                        <AlertTriangle className="size-3.5" /> Short {line.shortfall}
                      </Badge>
                    )}
                  </TableCell>
                  {canWrite && (
                    <TableCell>
                      <Button variant="ghost" size="icon-sm" aria-label="Remove line" onClick={() => setRemoveLine(line)}>
                        <Trash2 className="size-4 text-muted-foreground" />
                      </Button>
                    </TableCell>
                  )}
                </TableRow>
              ))}
            </TableBody>
          </Table>
          {canWrite && (
            <div className="border-t px-4 py-3">
              <Button size="sm" variant="outline" onClick={() => setLineOpen(true)}>
                <Plus className="size-4" />
                Add line
              </Button>
            </div>
          )}
        </Card>

        <BuildHistory builds={project.builds} />
      </div>

      <EditProjectDialog project={project} open={editOpen} onOpenChange={setEditOpen} />
      <NewRevisionDialog project={project} open={revisionOpen} onOpenChange={setRevisionOpen} />
      <AddLineDialog projectId={project.id} partOptions={partOptions} open={lineOpen} onOpenChange={setLineOpen} />

      {/* Remove line confirmation */}
      <AlertDialog open={removeLine !== null} onOpenChange={(o) => !o && setRemoveLine(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove this line?</AlertDialogTitle>
            <AlertDialogDescription>
              {removeLine?.designation || removeLine?.raw_reference || 'This line'} is removed from the project. Stock is not affected.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (removeLine) router.delete(`/projects/${project.id}/project_lines/${removeLine.id}`, { preserveScroll: true })
                setRemoveLine(null)
              }}
            >
              Remove
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Build confirmation */}
      <AlertDialog open={buildOpen} onOpenChange={setBuildOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Build this project?</AlertDialogTitle>
            <AlertDialogDescription>
              This deducts the required quantity of every matched part from stock, times the number of kits, recording an outgoing movement for each and an entry in the build history. This can't be undone automatically.
              {project.reserved && ' The project\'s stock reservation is released once built.'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <div className="grid gap-4 sm:grid-cols-[120px_1fr]">
            <div className="space-y-2">
              <Label htmlFor="build-kits">Kits</Label>
              <Input id="build-kits" type="number" min={1} value={kits} onChange={(e) => setKits(e.target.value)} className="font-mono" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="build-note">Note</Label>
              <Input
                id="build-note"
                value={buildNote}
                maxLength={255}
                onChange={(e) => setBuildNote(e.target.value)}
                placeholder="Optional, e.g. workshop of 12 October"
              />
            </div>
          </div>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction disabled={!kitsValid} onClick={build}>
              Deduct stock
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </AppLayout>
  )
}

function SummaryCard({ label, value, tone }: { label: string; value: string | number; tone?: 'amber' | 'red' }) {
  const toneClass = tone === 'amber' ? 'text-amber-600 dark:text-amber-400' : tone === 'red' ? 'text-red-600 dark:text-red-400' : ''
  return (
    <Card>
      <CardContent>
        <div className="text-sm text-muted-foreground">{label}</div>
        <div className={`mt-1 font-mono text-2xl font-bold ${toneClass}`}>{value}</div>
      </CardContent>
    </Card>
  )
}

function BuildHistory({ builds }: { builds: ProjectBuild[] }) {
  if (builds.length === 0) return null

  return (
    <Card className="overflow-hidden py-0">
      <div className="flex items-center gap-2 border-b px-4 py-3">
        <History className="size-4 text-muted-foreground" />
        <h2 className="text-sm font-semibold">Build history</h2>
      </div>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Date</TableHead>
            <TableHead className="text-right">Kits</TableHead>
            <TableHead className="text-right">Parts taken</TableHead>
            <TableHead>By</TableHead>
            <TableHead>Note</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {builds.map((build) => (
            <TableRow key={build.id}>
              <TableCell className="text-sm">{new Date(build.built_at).toLocaleString()}</TableCell>
              <TableCell className="text-right font-mono">{build.quantity}</TableCell>
              <TableCell className="text-right font-mono text-muted-foreground">
                {build.units} ({build.references} ref{build.references !== 1 ? 's' : ''})
              </TableCell>
              <TableCell className="text-sm">{build.user ?? '—'}</TableCell>
              <TableCell className="max-w-[320px] truncate text-sm text-muted-foreground" title={build.note ?? undefined}>
                {build.note ?? ''}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </Card>
  )
}

interface DialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

function EditProjectDialog({ project, open, onOpenChange }: DialogProps & { project: Project }) {
  const [name, setName] = useState(project.name)
  const [revision, setRevision] = useState(project.revision ?? '')
  const [description, setDescription] = useState(project.description ?? '')
  const [processing, setProcessing] = useState(false)

  const openChange = (next: boolean) => {
    if (next) {
      setName(project.name)
      setRevision(project.revision ?? '')
      setDescription(project.description ?? '')
    }
    onOpenChange(next)
  }

  const submit = (e: FormEvent) => {
    e.preventDefault()
    setProcessing(true)
    router.patch(
      `/projects/${project.id}`,
      { project: { name: name.trim(), revision: revision.trim(), description: description.trim() } },
      { preserveScroll: true, onSuccess: () => onOpenChange(false), onFinish: () => setProcessing(false) }
    )
  }

  return (
    <Dialog open={open} onOpenChange={openChange}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Edit project</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="grid gap-4 sm:grid-cols-[1fr_100px]">
              <div className="space-y-2">
                <Label htmlFor="edit-project-name">Name</Label>
                <Input id="edit-project-name" value={name} onChange={(e) => setName(e.target.value)} required />
              </div>
              <div className="space-y-2">
                <Label htmlFor="edit-project-revision">Revision</Label>
                <Input id="edit-project-revision" value={revision} maxLength={20} onChange={(e) => setRevision(e.target.value)} placeholder="A" />
              </div>
            </div>
            <div className="space-y-2">
              <Label htmlFor="edit-project-description">Description</Label>
              <Textarea
                id="edit-project-description"
                value={description}
                maxLength={255}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="What this board or kit is for"
              />
            </div>
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={processing || name.trim().length < 2}>
              Save
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

function NewRevisionDialog({ project, open, onOpenChange }: DialogProps & { project: Project }) {
  const [revision, setRevision] = useState(project.next_revision)
  const [processing, setProcessing] = useState(false)

  const openChange = (next: boolean) => {
    if (next) setRevision(project.next_revision)
    onOpenChange(next)
  }

  const submit = (e: FormEvent) => {
    e.preventDefault()
    setProcessing(true)
    router.post(
      `/projects/${project.id}/duplicate`,
      { revision: revision.trim() },
      { onSuccess: () => onOpenChange(false), onFinish: () => setProcessing(false) }
    )
  }

  return (
    <Dialog open={open} onOpenChange={openChange}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>New revision</DialogTitle>
            <DialogDescription>
              Copies {project.revision ? `revision ${project.revision}` : 'this project'} and its {project.lines.length} line
              {project.lines.length !== 1 ? 's' : ''} into a new draft project, with the same matches. This one stays as it is, with its build history.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2 py-4">
            <Label htmlFor="new-revision">Revision</Label>
            <Input id="new-revision" value={revision} maxLength={20} onChange={(e) => setRevision(e.target.value)} className="w-32 font-mono" />
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={processing}>
              <Copy className="size-4" />
              Create revision
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

function AddLineDialog({
  projectId,
  partOptions,
  open,
  onOpenChange,
}: DialogProps & { projectId: number; partOptions: ComboboxOption[] }) {
  const [partId, setPartId] = useState(NONE)
  const [designation, setDesignation] = useState('')
  const [reference, setReference] = useState('')
  const [designators, setDesignators] = useState('')
  const [quantity, setQuantity] = useState('1')
  const [processing, setProcessing] = useState(false)

  const reset = () => {
    setPartId(NONE)
    setDesignation('')
    setReference('')
    setDesignators('')
    setQuantity('1')
  }

  const quantityValue = Number(quantity)
  const valid =
    Number.isInteger(quantityValue) && quantityValue >= 1 && (partId !== NONE || designation.trim() !== '' || reference.trim() !== '')

  const submit = (e: FormEvent) => {
    e.preventDefault()
    if (!valid) return
    setProcessing(true)
    router.post(
      `/projects/${projectId}/project_lines`,
      {
        project_line: {
          part_id: partId === NONE ? '' : partId,
          designation: designation.trim(),
          raw_reference: reference.trim(),
          designators: designators.trim(),
          quantity: quantityValue,
        },
      },
      {
        preserveScroll: true,
        onSuccess: () => {
          reset()
          onOpenChange(false)
        },
        onFinish: () => setProcessing(false),
      }
    )
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Add line</DialogTitle>
            <DialogDescription>
              Pick a part from the inventory, or describe a component you don't stock yet so it shows up as missing.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="line-part">Part</Label>
              <Combobox
                id="line-part"
                options={partOptions}
                value={partId}
                onValueChange={(value) => setPartId(value || NONE)}
                placeholder="Not in inventory"
                searchPlaceholder="Search parts…"
                className="w-full"
              />
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="line-designation">Designation</Label>
                <Input
                  id="line-designation"
                  value={designation}
                  onChange={(e) => setDesignation(e.target.value)}
                  placeholder={partId === NONE ? 'e.g. ESP32-C3 module' : 'Defaults to the part name'}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="line-reference">Reference (MPN)</Label>
                <Input
                  id="line-reference"
                  value={reference}
                  onChange={(e) => setReference(e.target.value)}
                  placeholder={partId === NONE ? 'Optional' : 'Defaults to the part MPN'}
                />
              </div>
            </div>
            <div className="grid gap-4 sm:grid-cols-[1fr_120px]">
              <div className="space-y-2">
                <Label htmlFor="line-designators">Designators</Label>
                <Input id="line-designators" value={designators} onChange={(e) => setDesignators(e.target.value)} placeholder="e.g. R1, R2" />
              </div>
              <div className="space-y-2">
                <Label htmlFor="line-quantity">Quantity</Label>
                <Input
                  id="line-quantity"
                  type="number"
                  min={1}
                  value={quantity}
                  onChange={(e) => setQuantity(e.target.value)}
                  className="font-mono"
                />
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={processing || !valid}>
              <Plus className="size-4" />
              Add line
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
