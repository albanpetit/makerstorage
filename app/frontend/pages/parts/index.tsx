import { Head } from '@inertiajs/react'
import { useMemo, useState } from 'react'
import { Plus, Search, Download, Upload } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { SidebarTrigger } from '@/components/ui/sidebar'
import { usePermissions } from '@/hooks/use-permissions'
import { ReadOnlyBadge } from '@/components/read-only-badge'
import { FlashMessages } from '@/components/flash-messages'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { AddPartDialog } from '@/components/add-part-dialog'
import { EditPartDialog } from '@/components/edit-part-dialog'
import { PartDetailSheet } from '@/components/part-detail-sheet'
import { BulkActions } from '@/components/parts/bulk-actions'
import { exportCsv } from '@/components/parts/csv'
import { ImportPartsDialog } from '@/components/parts/import-parts-dialog'
import { PartsFilterBar } from '@/components/parts/parts-filter-bar'
import { PartsTable } from '@/components/parts/parts-table'
import type { PartsIndexProps } from '@/components/parts/types'
import { usePartFilters } from '@/components/parts/use-part-filters'

export default function PartsIndex({ parts, initial_query, categories, footprints, suppliers, tags, storage_locations, supplier_lookup_enabled, ipn_manual_entry, open_add }: PartsIndexProps) {
  const { canWrite } = usePermissions()
  const filters = usePartFilters(parts, initial_query)
  const { query, setQuery, filtered, sorted } = filters
  const [selected, setSelected] = useState<number[]>([])
  const [page, setPage] = useState(0)

  const [importOpen, setImportOpen] = useState(false)

  const [addOpen, setAddOpen] = useState(open_add)
  const openAddDialog = () => setAddOpen(true)

  const [editPartId, setEditPartId] = useState<number | null>(null)
  const [detailPartId, setDetailPartId] = useState<number | null>(null)

  const totalUnits = useMemo(() => filtered.reduce((sum, part) => sum + part.total_quantity, 0), [filtered])

  const hiddenSelectedCount = useMemo(() => {
    const visible = new Set(sorted.map((p) => p.id))
    return selected.filter((id) => !visible.has(id)).length
  }, [sorted, selected])

  const selectedParts = useMemo(() => parts.filter((p) => selected.includes(p.id)), [parts, selected])

  return (
    <AppLayout>
      <Head title="Parts" />

      <div className="-m-4 flex h-[100svh] flex-col">
        {/* Topbar */}
        <div className="flex shrink-0 flex-wrap items-center gap-3 border-b bg-background px-4 py-3 sm:px-5">
          <SidebarTrigger className="-ml-1 md:hidden" />
          <div>
            <h1 className="text-base font-semibold tracking-tight">Inventory</h1>
            <p className="text-xs text-muted-foreground">
              {filtered.length} reference{filtered.length !== 1 ? 's' : ''} · {totalUnits.toLocaleString()} units in stock
            </p>
          </div>
          <div className="flex-1" />
          <div className="relative w-full sm:w-64">
            <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              placeholder="Reference, value, location…"
              className="pl-9"
              value={query}
              onChange={(e) => { setQuery(e.target.value); setPage(0) }}
            />
          </div>
          <ReadOnlyBadge />
          {canWrite && (
            <Button variant="outline" size="sm" onClick={() => setImportOpen(true)}>
              <Upload className="size-4" />
              Import CSV
            </Button>
          )}
          <Button variant="outline" size="sm" onClick={() => exportCsv(sorted)}>
            <Download className="size-4" />
            Export CSV
          </Button>
          {canWrite && (
            <Button size="sm" onClick={openAddDialog}>
              <Plus className="size-4" />
              Add Part
            </Button>
          )}
        </div>

        <div className="px-5 pt-3 empty:pt-0">
          <FlashMessages />
        </div>

        <PartsFilterBar filters={filters} totalCount={parts.length} onFilterChange={() => setPage(0)} />

        <BulkActions
          selected={selected}
          selectedParts={selectedParts}
          hiddenSelectedCount={hiddenSelectedCount}
          onClearSelection={() => setSelected([])}
          categories={categories}
          suppliers={suppliers}
          tags={tags}
          storageLocations={storage_locations}
        />

        <PartsTable
          parts={parts}
          filtered={filtered}
          sorted={sorted}
          selected={selected}
          onSelectedChange={setSelected}
          page={page}
          onPageChange={setPage}
          onAddPart={openAddDialog}
          onShowPart={setDetailPartId}
          onEditPart={setEditPartId}
        />
      </div>

      {/* Add Part modal */}
      <AddPartDialog
        open={addOpen}
        onOpenChange={setAddOpen}
        categories={categories}
        footprints={footprints}
        suppliers={suppliers}
        tags={tags}
        storageLocations={storage_locations}
        supplierLookupEnabled={supplier_lookup_enabled}
        ipnManualEntry={ipn_manual_entry}
      />

      {/* Edit Part modal */}
      <EditPartDialog
        partId={editPartId}
        open={editPartId !== null}
        onOpenChange={(open) => !open && setEditPartId(null)}
        categories={categories}
        footprints={footprints}
        suppliers={suppliers}
        tags={tags}
        supplierLookupEnabled={supplier_lookup_enabled}
        ipnManualEntry={ipn_manual_entry}
      />

      {/* Part detail sidebar */}
      <PartDetailSheet
        partId={detailPartId}
        open={detailPartId !== null}
        onOpenChange={(open) => !open && setDetailPartId(null)}
      />

      <ImportPartsDialog open={importOpen} onOpenChange={setImportOpen} parts={parts} />
    </AppLayout>
  )
}
