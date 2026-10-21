import { Head, Link } from '@inertiajs/react'
import { useMemo, useRef, useState } from 'react'
import { Plus, Search, Download, Upload, Copy } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { SidebarTrigger } from '@/components/ui/sidebar'
import { usePermissions } from '@/hooks/use-permissions'
import { ReadOnlyBadge } from '@/components/read-only-badge'
import { FlashMessages } from '@/components/flash-messages'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { AddPartDialog } from '@/components/add-part-dialog'
import { EditPartDialog } from '@/components/edit-part-dialog'
import { PartDetailSheet } from '@/components/part-detail-sheet'
import { BulkActions } from '@/components/parts/bulk-actions'
import { exportCsv, fetchPartRows } from '@/components/parts/csv'
import { toast } from 'sonner'
import { ImportPartsDialog } from '@/components/parts/import-parts-dialog'
import { PartsFilterBar } from '@/components/parts/parts-filter-bar'
import { PartsTable } from '@/components/parts/parts-table'
import type { Part, PartsIndexProps } from '@/components/parts/types'
import { usePartFilters } from '@/components/parts/use-part-filters'
import { t, tn } from '@/lib/i18n'

export default function PartsIndex({
  parts, filters: listFilters, pagination, facets, parameter_columns, total_count, total_units, matching_ids, part_identifiers,
  categories, footprints, suppliers, tags, storage_locations, supplier_lookup_enabled, ipn_manual_entry, bag_options, bag_boxes, open_add, add_prefill,
  duplicate_groups_count,
}: PartsIndexProps) {
  const { canWrite } = usePermissions()
  const filters = usePartFilters(listFilters, facets)
  const { query, setQuery, goToPage } = filters
  // Selection survives page and filter changes, so it can hold parts that are
  // not on the current page.
  const [selected, setSelected] = useState<number[]>([])

  const [importOpen, setImportOpen] = useState(false)

  const [addOpen, setAddOpen] = useState(open_add)
  const openAddDialog = () => setAddOpen(true)

  const [editPartId, setEditPartId] = useState<number | null>(null)
  const [detailPartId, setDetailPartId] = useState<number | null>(null)

  // Every part seen on a page so far, so bulk labels/export only fetch the
  // selected parts that were never displayed.
  const knownParts = useRef(new Map<number, Part>())
  parts.forEach((part) => knownParts.current.set(part.id, part))

  const hiddenSelectedCount = useMemo(() => {
    const visible = new Set(matching_ids)
    return selected.filter((id) => !visible.has(id)).length
  }, [matching_ids, selected])

  const loadSelectedParts = async () => {
    const missing = selected.filter((id) => !knownParts.current.has(id))
    if (missing.length > 0) {
      const fetched = await fetchPartRows({ part_ids: missing })
      fetched.forEach((part) => knownParts.current.set(part.id, part))
    }
    return selected.flatMap((id) => knownParts.current.get(id) ?? [])
  }

  const exportMatching = () => {
    fetchPartRows({ filters: listFilters })
      .then(exportCsv)
      .catch(() => toast.error(t('Could not export the parts.')))
  }

  return (
    <AppLayout>
      <Head title={t('Parts')} />

      <div className="-m-4 flex h-[100svh] flex-col">
        {/* Topbar */}
        <div className="flex shrink-0 flex-wrap items-center gap-3 border-b bg-background px-4 py-3 sm:px-5">
          <SidebarTrigger className="-ml-1 md:hidden" />
          <div>
            <h1 className="text-base font-semibold tracking-tight">{t('Inventory')}</h1>
            <p className="text-xs text-muted-foreground">
              {tn('{count} reference', '{count} references', pagination.total)} · {tn('{count} unit in stock', '{count} units in stock', total_units)}
            </p>
          </div>
          <div className="flex-1" />
          <div className="relative w-full sm:w-64">
            <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              placeholder={t('Reference, value, location…')}
              className="pl-9"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </div>
          <ReadOnlyBadge />
          {duplicate_groups_count > 0 && (
            <Button variant="outline" size="sm" asChild>
              <Link href="/parts/duplicates">
                <Copy className="size-4" />
                {t('Duplicates')}
                <Badge variant="secondary" className="ml-0.5 px-1.5">{duplicate_groups_count}</Badge>
              </Link>
            </Button>
          )}
          {canWrite && (
            <Button variant="outline" size="sm" onClick={() => setImportOpen(true)}>
              <Upload className="size-4" />
              {t('Import CSV')}
            </Button>
          )}
          <Button variant="outline" size="sm" onClick={exportMatching}>
            <Download className="size-4" />
            {t('Export CSV')}
          </Button>
          {canWrite && (
            <Button size="sm" onClick={openAddDialog}>
              <Plus className="size-4" />
              {t('Add Part')}
            </Button>
          )}
        </div>

        <div className="px-5 pt-3 empty:pt-0">
          <FlashMessages />
        </div>

        <PartsFilterBar filters={filters} totalCount={total_count} />

        <BulkActions
          selected={selected}
          loadSelectedParts={loadSelectedParts}
          hiddenSelectedCount={hiddenSelectedCount}
          onClearSelection={() => setSelected([])}
          categories={categories}
          suppliers={suppliers}
          tags={tags}
          storageLocations={storage_locations}
        />

        <PartsTable
          parts={parts}
          totalCount={total_count}
          matchingIds={matching_ids}
          pagination={pagination}
          selected={selected}
          onSelectedChange={setSelected}
          onPageChange={goToPage}
          onAddPart={openAddDialog}
          onShowPart={setDetailPartId}
          onEditPart={setEditPartId}
          parameterColumns={parameter_columns}
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
        bagOptions={bag_options}
        bagBoxes={bag_boxes}
        prefill={add_prefill}
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

      <ImportPartsDialog open={importOpen} onOpenChange={setImportOpen} identifiers={part_identifiers} />
    </AppLayout>
  )
}
