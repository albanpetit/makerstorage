import { Head, useForm, router } from '@inertiajs/react'
import { FormEvent, useEffect, useState } from 'react'
import {
  Search,
  Plus,
  ChevronRight,
  ChevronLeft,
  Archive,
  Pencil,
  Printer,
  Trash2,
} from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { SidebarTrigger } from '@/components/ui/sidebar'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { ReadOnlyBadge } from '@/components/read-only-badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { PrintLabelsDialog } from '@/components/print-labels-dialog'
import { labelCodeForZone } from '@/lib/labels'
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
import { FlashMessages } from '@/components/flash-messages'
import { MoveStockDialog } from '@/components/storage-locations/move-stock-dialog'
import { SubZoneGrid } from '@/components/storage-locations/sub-zone-grid'
import type {
  MoveDialogState, MoveRow, PartStorageEntry, StorageLocationsPageProps, ZoneFormData,
} from '@/components/storage-locations/types'
import { useZoneTree } from '@/components/storage-locations/use-zone-tree'
import { ZoneComponentsTable } from '@/components/storage-locations/zone-components-table'
import { ZoneFormDialog } from '@/components/storage-locations/zone-form-dialog'
import { ZoneHistory } from '@/components/storage-locations/zone-history'
import { typeMeta } from '@/components/storage-locations/zone-meta'

export default function StorageLocationsIndex({ storage_locations, part_storages, recent_movements, selected_zone_id }: StorageLocationsPageProps) {
  const { canWrite } = usePermissions()
  const [query, setQuery] = useState('')
  const [selectedId, setSelectedId] = useState<number | null>(selected_zone_id ?? null)
  // On phones the tree and detail can't sit side-by-side, so we swap between
  // them: false shows the tree, true shows the selected zone's detail. Ignored
  // at lg+ where both panels are always visible.
  const [mobileDetail, setMobileDetail] = useState(selected_zone_id != null)
  const [newOpen, setNewOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [labelsOpen, setLabelsOpen] = useState(false)
  const [labelSubZones, setLabelSubZones] = useState(false)

  // Drag-and-drop re-parenting state
  const [dragId, setDragId] = useState<number | null>(null)
  const [dropTargetId, setDropTargetId] = useState<number | 'root' | null>(null)

  // Moving components between zones: which parts are checked in the current
  // zone's table, which parts are mid-drag, and the pending move dialog.
  const [selectedPartIds, setSelectedPartIds] = useState<Set<number>>(new Set())
  const [draggingPartIds, setDraggingPartIds] = useState<number[] | null>(null)
  const [moveDialog, setMoveDialog] = useState<MoveDialogState | null>(null)

  const tree = useZoneTree(storage_locations, part_storages, query)
  const {
    byId, childrenByParent, partStoragesByLocation, aggCounts, subtreeIds, pathOf,
    visibleIds, treeRows, expanded, setExpanded, toggleExpand, expandAll, collapseAll,
    parentOptions, allZoneOptions,
  } = tree

  const roots = childrenByParent.get(null) || []
  const selected = selectedId != null ? byId.get(selectedId) : undefined
  const effectiveSelected = selected || roots[0]

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

  // A zone can be dropped anywhere except onto itself or one of its own
  // descendants (which would create a cycle). 'root' means the top level.
  function canDropOn(targetId: number | 'root'): boolean {
    if (dragId == null) return false
    if (targetId === 'root') return byId.get(dragId)?.parent_id != null
    return targetId !== dragId && !subtreeIds(dragId).includes(targetId)
  }

  function moveZone(id: number, newParentId: number | null) {
    const rec = byId.get(id)
    if (!rec || (rec.parent_id ?? null) === (newParentId ?? null)) return
    router.patch(`/storage_locations/${id}`, { storage_location: { parent_id: newParentId } }, {
      preserveScroll: true,
      preserveState: true,
      onSuccess: () => {
        if (newParentId != null) setExpanded((prev) => new Set(prev).add(newParentId))
      },
    })
  }

  function endDrag() {
    setDragId(null)
    setDropTargetId(null)
  }

  // Clear the component selection whenever the viewed zone changes — the
  // checkboxes only make sense against the currently displayed table.
  useEffect(() => {
    setSelectedPartIds(new Set())
  }, [effectiveSelected?.id])


  // Build editable move rows for the given parts, sourced from the zone they
  // currently live in (their full on-hand quantity is the max and the default).
  function buildMoveRows(fromZoneId: number, partIds: number[]): MoveRow[] {
    const entries = partStoragesByLocation.get(fromZoneId) || []
    return partIds
      .map((partId) => entries.find((e) => e.part.id === partId))
      .filter((e): e is PartStorageEntry => e != null && e.quantity > 0)
      .map((e) => ({ partId: e.part.id, reference: e.part.reference, name: e.part.name, quantity: e.quantity, max: e.quantity }))
  }

  // Drop onto a target zone → open the dialog with the destination fixed.
  function openMoveFromDrop(fromZoneId: number, toZoneId: number, partIds: number[]) {
    const rows = buildMoveRows(fromZoneId, partIds)
    if (rows.length === 0) return
    setMoveDialog({ mode: 'fixed', fromId: fromZoneId, toId: toZoneId, rows })
  }

  // Bulk "Move to…" button → open the dialog with a destination picker.
  function openBulkMove() {
    if (!effectiveSelected) return
    const rows = buildMoveRows(effectiveSelected.id, [ ...selectedPartIds ])
    if (rows.length === 0) return
    setMoveDialog({ mode: 'select', fromId: effectiveSelected.id, toId: null, rows })
  }


  const moveDialogValid =
    moveDialog != null &&
    moveDialog.toId != null &&
    moveDialog.toId !== moveDialog.fromId &&
    moveDialog.rows.length > 0 &&
    moveDialog.rows.every((r) => Number.isFinite(r.quantity) && r.quantity >= 1 && r.quantity <= r.max)

  function submitMove() {
    if (!moveDialog || !moveDialogValid) return
    router.post('/storage_locations/move_stock', {
      from_location_id: moveDialog.fromId,
      to_location_id: moveDialog.toId,
      moves: moveDialog.rows.map((r) => ({ part_id: r.partId, quantity: r.quantity })),
    }, {
      preserveScroll: true,
      onSuccess: () => {
        setMoveDialog(null)
        setSelectedPartIds(new Set())
      },
    })
  }

  // Dragging a checked row carries the whole selection; otherwise just that part.
  function startComponentDrag(partId: number) {
    setDraggingPartIds(selectedPartIds.has(partId) ? [ ...selectedPartIds ] : [ partId ])
  }

  function endComponentDrag() {
    setDraggingPartIds(null)
    setDropTargetId(null)
  }

  function toggleSelectPart(partId: number) {
    setSelectedPartIds((prev) => {
      const next = new Set(prev)
      if (next.has(partId)) next.delete(partId)
      else next.add(partId)
      return next
    })
  }

  const newZoneDialog = (
    <ZoneFormDialog
      mode="new"
      open={newOpen}
      onOpenChange={setNewOpen}
      form={newForm}
      onSubmit={submitNew}
      parentOptions={parentOptions()}
    />
  )

  if (storage_locations.length === 0) {
    return (
      <AppLayout
        header={<PageHeader title="Storage Zones" subtitle="Organize your locations hierarchically" />}
      >
        <Head title="Storage Zones" />
        <FlashMessages />
        <div className="space-y-6">
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
        {newZoneDialog}
      </AppLayout>
    )
  }

  const selMeta = effectiveSelected ? typeMeta(effectiveSelected.location_type) : null
  const selChildren = effectiveSelected ? childrenByParent.get(effectiveSelected.id) || [] : []
  const selDirect = effectiveSelected ? partStoragesByLocation.get(effectiveSelected.id) || [] : []
  const selAgg = effectiveSelected ? aggCounts(effectiveSelected.id) : { refs: 0, units: 0 }
  const path = effectiveSelected ? pathOf(effectiveSelected.id) : []
  const parent = effectiveSelected?.parent_id != null ? byId.get(effectiveSelected.parent_id) : undefined

  const labelZoneIds = effectiveSelected
    ? (labelSubZones ? subtreeIds(effectiveSelected.id) : [ effectiveSelected.id ])
    : []
  const zoneLabels = labelZoneIds.flatMap((id) => {
    const zone = byId.get(id)
    if (!zone) return []
    const zonePath = pathOf(id).map((z) => z.name)
    return [ {
      code: labelCodeForZone(zone),
      title: zone.name,
      lines: [ zonePath.length > 1 ? zonePath.slice(0, -1).join(' › ') : '', typeMeta(zone.location_type).label ],
    } ]
  })
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

  return (
    <AppLayout>
      <Head title="Storage Zones" />

      <div className="-m-4 flex h-[100svh] flex-col">
        <div className="flex shrink-0 flex-wrap items-center gap-3 border-b bg-background px-4 py-3 sm:px-5">
          <SidebarTrigger className="-ml-1 md:hidden" />
          <div>
            <h1 className="text-base font-semibold tracking-tight">Storage Zones</h1>
            <p className="text-xs text-muted-foreground">Organize your locations hierarchically</p>
          </div>
          <div className="flex-1" />
          <div className="relative w-full sm:w-64">
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

        <div className="shrink-0 border-b bg-background px-5 py-3 empty:hidden">
          <FlashMessages />
        </div>

        <div className="flex min-h-0 flex-1">
          {/* Tree explorer */}
          <div className={`${mobileDetail ? 'hidden' : 'flex'} w-full flex-col border-r bg-card lg:flex lg:w-72 lg:shrink-0`}>
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
                  const isDragging = dragId === row.location.id
                  // A component drag can drop on any zone except the one it came from.
                  const canDropComponents = draggingPartIds != null && effectiveSelected != null && row.location.id !== effectiveSelected.id
                  const isDropTarget = dropTargetId === row.location.id && (canDropOn(row.location.id) || canDropComponents)
                  return (
                    <div
                      key={row.location.id}
                      draggable={canWrite}
                      onClick={() => { setSelectedId(row.location.id); setMobileDetail(true) }}
                      onDragStart={canWrite ? (e) => {
                        setDragId(row.location.id)
                        e.dataTransfer.effectAllowed = 'move'
                        e.dataTransfer.setData('text/plain', String(row.location.id))
                      } : undefined}
                      onDragEnd={endDrag}
                      onDragOver={canWrite ? (e) => {
                        e.stopPropagation()
                        if (canDropOn(row.location.id) || canDropComponents) {
                          e.preventDefault()
                          e.dataTransfer.dropEffect = 'move'
                          setDropTargetId(row.location.id)
                        } else {
                          setDropTargetId(null)
                        }
                      } : undefined}
                      onDragLeave={() => setDropTargetId((cur) => (cur === row.location.id ? null : cur))}
                      onDrop={canWrite ? (e) => {
                        e.preventDefault()
                        e.stopPropagation()
                        if (draggingPartIds != null && effectiveSelected != null && canDropComponents) {
                          openMoveFromDrop(effectiveSelected.id, row.location.id, draggingPartIds)
                          endComponentDrag()
                        } else if (dragId != null && canDropOn(row.location.id)) {
                          moveZone(dragId, row.location.id)
                        }
                        endDrag()
                      } : undefined}
                      className={`flex cursor-pointer items-center gap-1.5 rounded-md py-1.5 pr-2 text-sm hover:bg-accent ${isSelected ? 'bg-muted font-semibold' : ''} ${isDragging ? 'opacity-50' : ''} ${isDropTarget ? 'ring-2 ring-inset ring-primary bg-accent' : ''}`}
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
              {canWrite && dragId != null && canDropOn('root') && (
                <div
                  onDragOver={(e) => { e.preventDefault(); e.dataTransfer.dropEffect = 'move'; setDropTargetId('root') }}
                  onDragLeave={() => setDropTargetId((cur) => (cur === 'root' ? null : cur))}
                  onDrop={(e) => { e.preventDefault(); if (dragId != null) moveZone(dragId, null); endDrag() }}
                  className={`mt-1 rounded-md border border-dashed px-2 py-2 text-center text-xs text-muted-foreground ${dropTargetId === 'root' ? 'border-primary bg-accent text-foreground' : ''}`}
                >
                  Drop here to move to top level
                </div>
              )}
            </div>
          </div>

          {/* Detail panel */}
          {effectiveSelected && selMeta && (
            <div className={`${mobileDetail ? 'block' : 'hidden'} min-w-0 flex-1 space-y-4 overflow-y-auto bg-muted/40 p-5 lg:block`}>
              <Button
                type="button"
                variant="ghost"
                onClick={() => setMobileDetail(false)}
                className="sticky top-0 z-10 -mx-5 -mt-5 mb-1 flex h-auto w-[calc(100%+2.5rem)] justify-start gap-1.5 rounded-none border-b bg-background/95 px-5 py-3 backdrop-blur has-[>svg]:px-5 lg:hidden"
              >
                <ChevronLeft className="size-4" />
                Back to zones
              </Button>
              <Breadcrumb>
                <BreadcrumbList>
                  {path.map((z, i) => (
                    <span key={z.id} className="flex items-center gap-1.5">
                      <BreadcrumbItem>
                        {i === path.length - 1 ? (
                          <BreadcrumbPage>{z.name}</BreadcrumbPage>
                        ) : (
                          <BreadcrumbLink asChild>
                            <Button
                              variant="link"
                              size="sm"
                              onClick={() => setSelectedId(z.id)}
                              className="h-auto p-0 font-normal text-muted-foreground hover:text-foreground hover:no-underline"
                            >
                              {z.name}
                            </Button>
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
                    <Button variant="outline" size="sm" onClick={() => setLabelsOpen(true)}>
                      <Printer className="size-4" />
                      Label
                    </Button>
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
              <SubZoneGrid
                subZones={selChildren}
                tree={tree}
                onSelect={setSelectedId}
                onAddHere={() => openNewDialog(effectiveSelected.id)}
              />

              {/* Components stored here */}
              <ZoneComponentsTable
                entries={selDirect}
                selectedPartIds={selectedPartIds}
                onSelectionChange={setSelectedPartIds}
                onToggle={toggleSelectPart}
                draggingPartIds={draggingPartIds}
                onDragStart={startComponentDrag}
                onDragEnd={endComponentDrag}
                onBulkMove={openBulkMove}
              />

              {/* Zone movement history */}
              <ZoneHistory movements={zoneHistory} />
            </div>
          )}
        </div>
      </div>

      {newZoneDialog}

      <ZoneFormDialog
        mode="edit"
        open={editOpen}
        onOpenChange={setEditOpen}
        form={editForm}
        onSubmit={submitEdit}
        parentOptions={parentOptions(effectiveSelected?.id)}
      />

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

      <PrintLabelsDialog
        open={labelsOpen}
        onOpenChange={setLabelsOpen}
        count={zoneLabels.length}
        loadItems={() => Promise.resolve(zoneLabels)}
        title={`Print labels for ${effectiveSelected?.name ?? 'zone'}`}
        description="Scanning a zone label opens the scanner on that zone and lists what it holds."
      >
        {effectiveSelected && (childrenByParent.get(effectiveSelected.id) || []).length > 0 && (
          <div className="flex items-center justify-between gap-3">
            <Label htmlFor="label-sub-zones">Include all sub-zones</Label>
            <Switch id="label-sub-zones" checked={labelSubZones} onCheckedChange={setLabelSubZones} />
          </div>
        )}
      </PrintLabelsDialog>

      <MoveStockDialog
        moveDialog={moveDialog}
        setMoveDialog={setMoveDialog}
        zoneOptions={allZoneOptions()}
        zoneName={(id) => byId.get(id)?.name}
        valid={moveDialogValid}
        onSubmit={submitMove}
      />
    </AppLayout>
  )
}
