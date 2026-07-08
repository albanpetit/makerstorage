import { Head, useForm, router } from '@inertiajs/react'
import { FormEvent, useMemo, useState } from 'react'
import {
  Search,
  Plus,
  ChevronRight,
  DoorOpen,
  Archive,
  Layers,
  Wrench,
  ArchiveRestore,
  Package,
  Pencil,
  Trash2,
  ArrowUpRight,
  type LucideIcon,
} from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { ReadOnlyBadge } from '@/components/read-only-badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'
import { Card, CardContent } from '@/components/ui/card'
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
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from '@/components/ui/breadcrumb'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { FlashMessages } from '@/components/flash-messages'

interface StorageLocationRecord {
  id: number
  name: string
  location_type: string
  code: string | null
  parent_id: number | null
}

interface PartStorageEntry {
  location_id: number
  quantity: number
  part: {
    id: number
    reference: string
    name: string
    package_type: string | null
  }
}

interface RecentMovement {
  location_id: number
  part_reference: string
  movement_type: 'in' | 'out' | 'adjustment'
  quantity_delta: number
  reason: string | null
  created_at: string
}

interface StorageLocationsPageProps {
  storage_locations: StorageLocationRecord[]
  part_storages: PartStorageEntry[]
  recent_movements: RecentMovement[]
}

const LOCATION_TYPES = ['room', 'cabinet', 'shelf', 'bench', 'drawer', 'box'] as const

const TYPE_META: Record<string, { label: string; icon: LucideIcon; className: string }> = {
  room: { label: 'Room', icon: DoorOpen, className: 'bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-400' },
  cabinet: { label: 'Cabinet', icon: Archive, className: 'bg-purple-100 text-purple-700 dark:bg-purple-950 dark:text-purple-400' },
  shelf: { label: 'Shelf', icon: Layers, className: 'bg-cyan-100 text-cyan-700 dark:bg-cyan-950 dark:text-cyan-400' },
  bench: { label: 'Bench', icon: Wrench, className: 'bg-pink-100 text-pink-700 dark:bg-pink-950 dark:text-pink-400' },
  drawer: { label: 'Drawer', icon: ArchiveRestore, className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
  box: { label: 'Box', icon: Package, className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
}

const MOVEMENT_META: Record<RecentMovement['movement_type'], { label: string; className: string }> = {
  in: { label: 'In', className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
  out: { label: 'Out', className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
  adjustment: { label: 'Adjustment', className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
}

function typeMeta(type: string) {
  return TYPE_META[type] || TYPE_META.box
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, { day: '2-digit', month: '2-digit', year: 'numeric' })
}

interface ZoneFormData {
  storage_location: {
    name: string
    location_type: string
    code: string
    parent_id: string
  }
}

export default function StorageLocationsIndex({ storage_locations, part_storages, recent_movements }: StorageLocationsPageProps) {
  const { canWrite } = usePermissions()
  const [query, setQuery] = useState('')
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [expanded, setExpanded] = useState<Set<number>>(
    () => new Set(storage_locations.filter((z) => storage_locations.some((c) => c.parent_id === z.id)).map((z) => z.id))
  )
  const [newOpen, setNewOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)

  const byId = useMemo(() => new Map(storage_locations.map((z) => [z.id, z])), [storage_locations])

  const childrenByParent = useMemo(() => {
    const map = new Map<number | null, StorageLocationRecord[]>()
    storage_locations.forEach((z) => {
      const key = z.parent_id
      if (!map.has(key)) map.set(key, [])
      map.get(key)!.push(z)
    })
    map.forEach((list) => list.sort((a, b) => a.name.localeCompare(b.name)))
    return map
  }, [storage_locations])

  const partStoragesByLocation = useMemo(() => {
    const map = new Map<number, PartStorageEntry[]>()
    part_storages.forEach((ps) => {
      if (!map.has(ps.location_id)) map.set(ps.location_id, [])
      map.get(ps.location_id)!.push(ps)
    })
    return map
  }, [part_storages])

  const roots = childrenByParent.get(null) || []
  const selected = selectedId != null ? byId.get(selectedId) : undefined
  const effectiveSelected = selected || roots[0]

  function aggCounts(id: number): { refs: number; units: number } {
    const direct = partStoragesByLocation.get(id) || []
    let refs = direct.length
    let units = direct.reduce((sum, ps) => sum + ps.quantity, 0)
    for (const child of childrenByParent.get(id) || []) {
      const agg = aggCounts(child.id)
      refs += agg.refs
      units += agg.units
    }
    return { refs, units }
  }

  function subtreeIds(id: number): number[] {
    const ids = [id]
    for (const child of childrenByParent.get(id) || []) {
      ids.push(...subtreeIds(child.id))
    }
    return ids
  }

  function pathOf(id: number): StorageLocationRecord[] {
    const path: StorageLocationRecord[] = []
    let current = byId.get(id)
    while (current) {
      path.unshift(current)
      current = current.parent_id != null ? byId.get(current.parent_id) : undefined
    }
    return path
  }

  const visibleIds = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return null
    const matches = new Set<number>()
    storage_locations.forEach((z) => {
      if (z.name.toLowerCase().includes(q) || (z.code || '').toLowerCase().includes(q)) {
        let current: StorageLocationRecord | undefined = z
        while (current) {
          matches.add(current.id)
          current = current.parent_id != null ? byId.get(current.parent_id) : undefined
        }
      }
    })
    return matches
  }, [query, storage_locations, byId])

  interface TreeRow {
    location: StorageLocationRecord
    depth: number
    hasChildren: boolean
    refCount: number
  }

  const treeRows = useMemo(() => {
    const rows: TreeRow[] = []
    const walk = (parentId: number | null, depth: number) => {
      const kids = (childrenByParent.get(parentId) || []).filter((z) => !visibleIds || visibleIds.has(z.id))
      kids.forEach((z) => {
        const hasChildren = (childrenByParent.get(z.id) || []).length > 0
        rows.push({ location: z, depth, hasChildren, refCount: aggCounts(z.id).refs })
        const isExpanded = visibleIds ? true : expanded.has(z.id)
        if (hasChildren && isExpanded) walk(z.id, depth + 1)
      })
    }
    walk(null, 0)
    return rows
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [childrenByParent, visibleIds, expanded, partStoragesByLocation])

  function toggleExpand(id: number) {
    setExpanded((prev) => {
      const next = new Set(prev)
      if (next.has(id)) {
        next.delete(id)
      } else {
        next.add(id)
      }
      return next
    })
  }

  function expandAll() {
    setExpanded(new Set(storage_locations.filter((z) => (childrenByParent.get(z.id) || []).length > 0).map((z) => z.id)))
  }

  function collapseAll() {
    setExpanded(new Set())
  }

  function parentOptions(excludeId?: number) {
    const excluded = excludeId != null ? new Set(subtreeIds(excludeId)) : new Set<number>()
    const options: { id: number; label: string }[] = []
    const walk = (parentId: number | null, depth: number) => {
      (childrenByParent.get(parentId) || []).forEach((z) => {
        if (!excluded.has(z.id)) {
          options.push({ id: z.id, label: `${'— '.repeat(depth)}${z.name}` })
          walk(z.id, depth + 1)
        }
      })
    }
    walk(null, 0)
    return options
  }

  const newForm = useForm<ZoneFormData>({
    storage_location: { name: '', location_type: 'box', code: '', parent_id: '' },
  })
  const editForm = useForm<ZoneFormData>({
    storage_location: { name: '', location_type: 'box', code: '', parent_id: '' },
  })

  function openNewDialog(parentId?: number | null) {
    newForm.clearErrors()
    newForm.setData('storage_location', {
      name: '',
      location_type: 'box',
      code: '',
      parent_id: parentId != null ? String(parentId) : '',
    })
    setNewOpen(true)
  }

  function submitNew(e: FormEvent) {
    e.preventDefault()
    newForm.post('/storage_locations', {
      preserveScroll: true,
      onSuccess: () => setNewOpen(false),
    })
  }

  function openEditDialog() {
    if (!effectiveSelected) return
    editForm.clearErrors()
    editForm.setData('storage_location', {
      name: effectiveSelected.name,
      location_type: effectiveSelected.location_type,
      code: effectiveSelected.code || '',
      parent_id: effectiveSelected.parent_id != null ? String(effectiveSelected.parent_id) : '',
    })
    setEditOpen(true)
  }

  function submitEdit(e: FormEvent) {
    e.preventDefault()
    if (!effectiveSelected) return
    editForm.patch(`/storage_locations/${effectiveSelected.id}`, {
      preserveScroll: true,
      onSuccess: () => setEditOpen(false),
    })
  }

  function confirmDelete() {
    if (!effectiveSelected) return
    const parentId = effectiveSelected.parent_id
    router.delete(`/storage_locations/${effectiveSelected.id}`, {
      preserveScroll: true,
      onSuccess: () => {
        setDeleteOpen(false)
        setSelectedId(parentId)
      },
    })
  }

  if (storage_locations.length === 0) {
    return (
      <AppLayout>
        <Head title="Storage Zones" />
        <FlashMessages />
        <div className="space-y-6">
          <div>
            <h1 className="text-2xl font-bold tracking-tight">Storage Zones</h1>
            <p className="text-muted-foreground text-sm">Organize your locations hierarchically</p>
          </div>
          <Card>
            <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
              <Archive className="size-8 text-muted-foreground" />
              <div>
                <p className="font-medium">No storage zones yet</p>
                <p className="text-sm text-muted-foreground">
                  {canWrite ? 'Create your first zone to start organizing your inventory.' : 'No storage zones have been created yet.'}
                </p>
              </div>
              {canWrite && (
                <Button onClick={() => openNewDialog(null)}>
                  <Plus className="size-4" />
                  New Zone
                </Button>
              )}
            </CardContent>
          </Card>
        </div>
        <NewZoneDialog />
      </AppLayout>
    )
  }

  const selMeta = effectiveSelected ? typeMeta(effectiveSelected.location_type) : null
  const selChildren = effectiveSelected ? childrenByParent.get(effectiveSelected.id) || [] : []
  const selDirect = effectiveSelected ? partStoragesByLocation.get(effectiveSelected.id) || [] : []
  const selAgg = effectiveSelected ? aggCounts(effectiveSelected.id) : { refs: 0, units: 0 }
  const path = effectiveSelected ? pathOf(effectiveSelected.id) : []
  const parent = effectiveSelected?.parent_id != null ? byId.get(effectiveSelected.parent_id) : undefined
  const zoneHistory = effectiveSelected
    ? (() => {
        const ids = new Set(subtreeIds(effectiveSelected.id))
        return recent_movements.filter((m) => ids.has(m.location_id)).slice(0, 8)
      })()
    : []

  const stats = effectiveSelected
    ? [
        { label: 'Direct sub-zones', value: String(selChildren.length) },
        { label: 'References (total)', value: String(selAgg.refs) },
        { label: 'Units (total)', value: selAgg.units.toLocaleString() },
        { label: 'Depth', value: `L${path.length}` },
      ]
    : []

  function NewZoneDialog() {
    return (
      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>New storage zone</DialogTitle>
          </DialogHeader>
          <form onSubmit={submitNew} className="flex flex-col gap-4">
            <Field>
              <FieldLabel>
                <Label>Zone name</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  placeholder="e.g. Box B2-T06"
                  value={newForm.data.storage_location.name}
                  onChange={(e) => newForm.setData('storage_location', { ...newForm.data.storage_location, name: e.target.value })}
                />
              </FieldContent>
              {newForm.errors['storage_location.name'] && <FieldError>{newForm.errors['storage_location.name']}</FieldError>}
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field>
                <FieldLabel>
                  <Label>Type</Label>
                </FieldLabel>
                <FieldContent>
                  <Select
                    value={newForm.data.storage_location.location_type}
                    onValueChange={(value) => newForm.setData('storage_location', { ...newForm.data.storage_location, location_type: value })}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {LOCATION_TYPES.map((t) => (
                        <SelectItem key={t} value={t}>{typeMeta(t).label}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FieldContent>
              </Field>
              <Field>
                <FieldLabel>
                  <Label>Parent zone</Label>
                </FieldLabel>
                <FieldContent>
                  <Select
                    value={newForm.data.storage_location.parent_id || 'none'}
                    onValueChange={(value) => newForm.setData('storage_location', { ...newForm.data.storage_location, parent_id: value === 'none' ? '' : value })}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">— Root (none) —</SelectItem>
                      {parentOptions().map((o) => (
                        <SelectItem key={o.id} value={String(o.id)}>{o.label}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FieldContent>
              </Field>
            </div>
            <Field>
              <FieldLabel>
                <Label>Code <span className="font-normal text-muted-foreground">(optional)</span></Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  placeholder="e.g. B2-T06"
                  value={newForm.data.storage_location.code}
                  onChange={(e) => newForm.setData('storage_location', { ...newForm.data.storage_location, code: e.target.value })}
                />
              </FieldContent>
              {newForm.errors['storage_location.code'] && <FieldError>{newForm.errors['storage_location.code']}</FieldError>}
            </Field>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setNewOpen(false)}>Cancel</Button>
              <Button type="submit" disabled={newForm.processing}>Create zone</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    )
  }

  return (
    <AppLayout>
      <Head title="Storage Zones" />
      <FlashMessages />

      <div className="-m-4 flex h-screen flex-col">
        <div className="flex shrink-0 flex-wrap items-center gap-3 border-b bg-background px-5 py-3">
          <div>
            <h1 className="text-base font-semibold tracking-tight">Storage Zones</h1>
            <p className="text-xs text-muted-foreground">Organize your locations hierarchically</p>
          </div>
          <div className="flex-1" />
          <div className="relative w-64">
            <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              placeholder="Search a zone…"
              className="pl-9"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </div>
          <ReadOnlyBadge />
          {canWrite && (
            <Button size="sm" onClick={() => openNewDialog(effectiveSelected?.id)}>
              <Plus className="size-4" />
              New Zone
            </Button>
          )}
        </div>

        <div className="flex min-h-0 flex-1">
          {/* Tree explorer */}
          <div className="flex w-72 shrink-0 flex-col border-r bg-card">
            <div className="flex shrink-0 items-center justify-between border-b px-3 py-2.5">
              <span className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Tree</span>
              <div className="flex gap-1">
                <Button variant="outline" size="sm" className="h-7 text-xs" onClick={expandAll}>Expand</Button>
                <Button variant="outline" size="sm" className="h-7 text-xs" onClick={collapseAll}>Collapse</Button>
              </div>
            </div>
            <div className="flex-1 overflow-y-auto p-2">
              {treeRows.length === 0 ? (
                <p className="p-4 text-center text-sm text-muted-foreground">No zone matches.</p>
              ) : (
                treeRows.map((row) => {
                  const meta = typeMeta(row.location.location_type)
                  const Icon = meta.icon
                  const isSelected = effectiveSelected?.id === row.location.id
                  const isExpanded = visibleIds ? true : expanded.has(row.location.id)
                  return (
                    <div
                      key={row.location.id}
                      onClick={() => setSelectedId(row.location.id)}
                      className={`flex cursor-pointer items-center gap-1.5 rounded-md py-1.5 pr-2 text-sm hover:bg-accent ${isSelected ? 'bg-muted font-semibold' : ''}`}
                      style={{ paddingLeft: `${8 + row.depth * 16}px` }}
                    >
                      <span
                        onClick={(e) => { e.stopPropagation(); if (row.hasChildren) toggleExpand(row.location.id) }}
                        className="flex size-4 shrink-0 items-center justify-center text-muted-foreground"
                      >
                        {row.hasChildren && (
                          <ChevronRight className={`size-3.5 transition-transform ${isExpanded ? 'rotate-90' : ''}`} />
                        )}
                      </span>
                      <Icon className={`size-4 shrink-0 ${meta.className.split(' ')[1]}`} />
                      <span className="min-w-0 flex-1 truncate">{row.location.name}</span>
                      {row.refCount > 0 && (
                        <Badge variant="secondary" className="shrink-0 font-mono text-[10px]">{row.refCount}</Badge>
                      )}
                    </div>
                  )
                })
              )}
            </div>
          </div>

          {/* Detail panel */}
          {effectiveSelected && selMeta && (
            <div className="min-w-0 flex-1 space-y-4 overflow-y-auto bg-muted/40 p-5">
              <Breadcrumb>
                <BreadcrumbList>
                  {path.map((z, i) => (
                    <span key={z.id} className="flex items-center gap-1.5">
                      <BreadcrumbItem>
                        {i === path.length - 1 ? (
                          <BreadcrumbPage>{z.name}</BreadcrumbPage>
                        ) : (
                          <BreadcrumbLink asChild>
                            <button onClick={() => setSelectedId(z.id)}>{z.name}</button>
                          </BreadcrumbLink>
                        )}
                      </BreadcrumbItem>
                      {i < path.length - 1 && <BreadcrumbSeparator />}
                    </span>
                  ))}
                </BreadcrumbList>
              </Breadcrumb>

              {/* Header card */}
              <Card>
                <CardContent className="flex flex-wrap items-start gap-4">
                  <div className={`flex size-12 shrink-0 items-center justify-center rounded-lg ${selMeta.className}`}>
                    <selMeta.icon className="size-6" />
                  </div>
                  <div className="min-w-[200px] flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <h1 className="text-lg font-bold tracking-tight">{effectiveSelected.name}</h1>
                      <Badge className={selMeta.className} variant="outline">{selMeta.label}</Badge>
                    </div>
                    <div className="mt-1.5 flex items-center gap-1.5 text-sm text-muted-foreground">
                      <span>{parent ? `In ${parent.name}` : 'Root zone'}</span>
                      {effectiveSelected.code && (
                        <>
                          <span className="opacity-50">·</span>
                          <span className="font-mono">{effectiveSelected.code}</span>
                        </>
                      )}
                    </div>
                  </div>
                  <div className="flex shrink-0 gap-2 empty:hidden">
                    {canWrite && (
                      <Button variant="outline" size="sm" onClick={openEditDialog}>
                        <Pencil className="size-4" />
                        Edit
                      </Button>
                    )}
                    {canWrite && (
                      <Button variant="outline" size="icon-sm" className="text-destructive" onClick={() => setDeleteOpen(true)}>
                        <Trash2 className="size-4" />
                      </Button>
                    )}
                  </div>
                </CardContent>
              </Card>

              {/* Stats */}
              <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
                {stats.map((s) => (
                  <Card key={s.label} className="py-3">
                    <CardContent className="px-4">
                      <div className="text-xs text-muted-foreground">{s.label}</div>
                      <div className="mt-1 font-mono text-xl font-bold">{s.value}</div>
                    </CardContent>
                  </Card>
                ))}
              </div>

              {/* Sub-zones */}
              <div>
                <div className="mb-2 flex items-center justify-between">
                  <h2 className="text-sm font-semibold">
                    Sub-zones <span className="font-normal text-muted-foreground">· {selChildren.length}</span>
                  </h2>
                  {canWrite && (
                    <Button variant="ghost" size="sm" className="text-xs text-muted-foreground" onClick={() => openNewDialog(effectiveSelected.id)}>
                      <Plus className="size-3.5" />
                      Add here
                    </Button>
                  )}
                </div>
                {selChildren.length > 0 ? (
                  <div className="grid gap-3 sm:grid-cols-2">
                    {selChildren.map((z) => {
                      const meta = typeMeta(z.location_type)
                      const agg = aggCounts(z.id)
                      const childCount = (childrenByParent.get(z.id) || []).length
                      return (
                        <Card key={z.id} className="cursor-pointer py-3 transition-colors hover:border-primary" onClick={() => setSelectedId(z.id)}>
                          <CardContent className="flex items-center gap-3 px-4">
                            <div className={`flex size-9 shrink-0 items-center justify-center rounded-lg ${meta.className}`}>
                              <meta.icon className="size-4.5" />
                            </div>
                            <div className="min-w-0 flex-1">
                              <div className="truncate text-sm font-semibold">{z.name}</div>
                              <div className="text-xs text-muted-foreground">
                                {meta.label}
                                {childCount > 0 && ` · ${childCount} sub-zone${childCount > 1 ? 's' : ''}`}
                                {` · ${agg.refs} ref${agg.refs !== 1 ? 's' : ''}`}
                              </div>
                            </div>
                            <ArrowUpRight className="size-4 shrink-0 text-muted-foreground" />
                          </CardContent>
                        </Card>
                      )
                    })}
                  </div>
                ) : (
                  <div className="rounded-lg border border-dashed p-5 text-center text-sm text-muted-foreground">
                    This zone has no sub-zone. It's a final storage location.
                  </div>
                )}
              </div>

              {/* Components stored here */}
              <div>
                <h2 className="mb-2 text-sm font-semibold">
                  Components stored here <span className="font-normal text-muted-foreground">· {selDirect.length}</span>
                </h2>
                {selDirect.length > 0 ? (
                  <Card className="gap-0 py-0">
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Reference</TableHead>
                          <TableHead>Name</TableHead>
                          <TableHead>Package</TableHead>
                          <TableHead className="text-right">Stock</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {selDirect.map((ps) => (
                          <TableRow key={ps.part.id}>
                            <TableCell className="font-mono text-sm font-semibold">{ps.part.reference}</TableCell>
                            <TableCell className="text-sm text-muted-foreground">{ps.part.name}</TableCell>
                            <TableCell>
                              {ps.part.package_type && (
                                <span className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">{ps.part.package_type}</span>
                              )}
                            </TableCell>
                            <TableCell className="text-right font-mono font-semibold">{ps.quantity}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </Card>
                ) : (
                  <div className="rounded-lg border border-dashed p-5 text-center text-sm text-muted-foreground">
                    No component directly in this zone — they're stored in the sub-zones above.
                  </div>
                )}
              </div>

              {/* Zone movement history */}
              <div>
                <div className="mb-2 flex items-center justify-between">
                  <h2 className="text-sm font-semibold">
                    Zone history <span className="font-normal text-muted-foreground">· subtree included</span>
                  </h2>
                </div>
                {zoneHistory.length > 0 ? (
                  <Card className="gap-0 py-0 divide-y">
                    {zoneHistory.map((m, i) => (
                      <div key={i} className="flex items-center gap-3 px-4 py-2.5 text-sm">
                        <Badge className={MOVEMENT_META[m.movement_type].className} variant="outline">
                          {MOVEMENT_META[m.movement_type].label}
                        </Badge>
                        <span className="shrink-0 font-mono font-semibold">{m.part_reference}</span>
                        <span className="min-w-0 flex-1 truncate text-muted-foreground">{m.reason}</span>
                        <span className="shrink-0 whitespace-nowrap text-xs text-muted-foreground">{formatDate(m.created_at)}</span>
                        <span className="w-12 shrink-0 text-right font-mono font-semibold">
                          {m.quantity_delta > 0 ? `+${m.quantity_delta}` : m.quantity_delta}
                        </span>
                      </div>
                    ))}
                  </Card>
                ) : (
                  <div className="rounded-lg border border-dashed p-5 text-center text-sm text-muted-foreground">
                    No movement recorded for this zone yet.
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      </div>

      <NewZoneDialog />

      {/* Edit zone dialog */}
      <Dialog open={editOpen} onOpenChange={setEditOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit zone</DialogTitle>
          </DialogHeader>
          <form onSubmit={submitEdit} className="flex flex-col gap-4">
            <Field>
              <FieldLabel>
                <Label>Zone name</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  value={editForm.data.storage_location.name}
                  onChange={(e) => editForm.setData('storage_location', { ...editForm.data.storage_location, name: e.target.value })}
                />
              </FieldContent>
              {editForm.errors['storage_location.name'] && <FieldError>{editForm.errors['storage_location.name']}</FieldError>}
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field>
                <FieldLabel>
                  <Label>Type</Label>
                </FieldLabel>
                <FieldContent>
                  <Select
                    value={editForm.data.storage_location.location_type}
                    onValueChange={(value) => editForm.setData('storage_location', { ...editForm.data.storage_location, location_type: value })}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {LOCATION_TYPES.map((t) => (
                        <SelectItem key={t} value={t}>{typeMeta(t).label}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FieldContent>
              </Field>
              <Field>
                <FieldLabel>
                  <Label>Parent zone <span className="font-normal text-muted-foreground">(move)</span></Label>
                </FieldLabel>
                <FieldContent>
                  <Select
                    value={editForm.data.storage_location.parent_id || 'none'}
                    onValueChange={(value) => editForm.setData('storage_location', { ...editForm.data.storage_location, parent_id: value === 'none' ? '' : value })}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">— Root (none) —</SelectItem>
                      {parentOptions(effectiveSelected?.id).map((o) => (
                        <SelectItem key={o.id} value={String(o.id)}>{o.label}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </FieldContent>
              </Field>
            </div>
            <Field>
              <FieldLabel>
                <Label>Code <span className="font-normal text-muted-foreground">(optional)</span></Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  value={editForm.data.storage_location.code}
                  onChange={(e) => editForm.setData('storage_location', { ...editForm.data.storage_location, code: e.target.value })}
                />
              </FieldContent>
              {editForm.errors['storage_location.code'] && <FieldError>{editForm.errors['storage_location.code']}</FieldError>}
            </Field>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setEditOpen(false)}>Cancel</Button>
              <Button type="submit" disabled={editForm.processing}>Save</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation */}
      <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete this zone?</AlertDialogTitle>
            <AlertDialogDescription>
              <span className="font-semibold text-foreground">{effectiveSelected?.name}</span> will be removed. A zone containing sub-zones cannot be deleted.
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
