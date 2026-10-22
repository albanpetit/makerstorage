import { useState } from 'react'
import { ChevronLeft, ChevronRight, Package, Pencil, Plus } from 'lucide-react'

import { usePermissions } from '@/hooks/use-permissions'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

import { LIFECYCLE_META, STOCK_STATUS_META, locationLabel, stockStatusKey } from './part-meta'
import type { Part, PartListPagination } from './types'
import { t } from '@/lib/i18n'

// Small square thumbnail for a part row. The URL may be a hotlinked supplier
// image (e.g. Mouser) that the browser can't load — fall back to the icon on
// error instead of showing a broken image.
function PartThumbnail({ url }: { url: string | null }) {
  const [failed, setFailed] = useState(false)

  return (
    <div className="flex size-9 shrink-0 items-center justify-center overflow-hidden rounded-md border bg-muted">
      {url && !failed ? (
        <img
          src={url}
          alt=""
          loading="lazy"
          onError={() => setFailed(true)}
          className="size-full object-cover"
        />
      ) : (
        <Package className="size-4 text-muted-foreground" />
      )}
    </div>
  )
}

interface PartsTableProps {
  // The current page of matching parts, already sorted by the server.
  parts: Part[]
  // How many parts the organization has (tells "no parts yet" from "nothing
  // matches the filters").
  totalCount: number
  // Every part matching the filters, across pages.
  matchingIds: number[]
  pagination: PartListPagination
  selected: number[]
  onSelectedChange: (ids: number[]) => void
  onPageChange: (page: number) => void
  onAddPart: () => void
  onShowPart: (id: number) => void
  onEditPart: (id: number) => void
  // Parameters shown as extra columns (the selected category's template).
  parameterColumns?: { id: number; name: string; unit: string | null }[]
}

// The paginated parts table with row/page selection, or an empty state.
export function PartsTable({
  parts, totalCount, matchingIds, pagination, selected, onSelectedChange,
  onPageChange, onAddPart, onShowPart, onEditPart, parameterColumns = [],
}: PartsTableProps) {
  const { canWrite } = usePermissions()

  const { page, page_count: pageCount, page_size: pageSize, total } = pagination
  const allFilteredSelected = matchingIds.length > 0 && matchingIds.every((id) => selected.includes(id))

  const pageIds = parts.map((p) => p.id)
  const pageAllSelected = pageIds.length > 0 && pageIds.every((id) => selected.includes(id))
  const pageSomeSelected = pageIds.some((id) => selected.includes(id))

  const toggleRow = (id: number) => {
    onSelectedChange(selected.includes(id) ? selected.filter((x) => x !== id) : [ ...selected, id ])
  }

  // Header checkbox scopes to the current page only — selecting every
  // matching part across pages is an explicit follow-up action (see banner
  // below), not an implicit side effect of "select all".
  const togglePage = () => {
    onSelectedChange(
      pageAllSelected
        ? selected.filter((id) => !pageIds.includes(id))
        : Array.from(new Set([ ...selected, ...pageIds ]))
    )
  }

  const selectAllMatching = () => onSelectedChange(Array.from(new Set([ ...selected, ...matchingIds ])))

  return (
    <div className="min-h-0 flex-1 overflow-auto bg-muted/40">
    {totalCount === 0 ? (
      <div className="flex flex-col items-center justify-center p-16">
        <Package className="size-12 text-muted-foreground" />
        <h3 className="mt-4 text-lg font-semibold">{t('No parts yet')}</h3>
        <p className="mt-2 text-sm text-muted-foreground">
          {canWrite ? t('Get started by adding your first part.') : t('No parts have been added yet.')}
        </p>
        {canWrite && (
          <Button className="mt-4" onClick={onAddPart}>
            <Plus className="mr-2 size-4" />
            {t('Add Part')}
          </Button>
        )}
      </div>
    ) : total === 0 ? (
      <div className="flex flex-col items-center justify-center p-16 text-center">
        <h3 className="text-lg font-semibold">{t('No results found')}</h3>
        <p className="mt-2 text-sm text-muted-foreground">
          {t('Try a different search or filter.')}
        </p>
      </div>
    ) : (
      <>
        <Table className="bg-background" containerClassName="overflow-visible">
          <TableHeader className="sticky top-0 z-10">
            <TableRow className="bg-muted hover:bg-muted">
              <TableHead className="w-10 py-2">
                <Checkbox
                  checked={pageAllSelected ? true : pageSomeSelected ? 'indeterminate' : false}
                  onCheckedChange={togglePage}
                  aria-label={t('Select page')}
                />
              </TableHead>
              <TableHead className="py-2">{t('Reference')}</TableHead>
              <TableHead className="py-2">{t('IPN')}</TableHead>
              <TableHead className="py-2">{t('Category')}</TableHead>
              <TableHead className="py-2">{t('Value')}</TableHead>
              {parameterColumns.map((column) => (
                <TableHead key={`param-${column.id}`} className="py-2">{column.name}</TableHead>
              ))}
              <TableHead className="py-2">{t('Package')}</TableHead>
              <TableHead className="py-2">{t('Location')}</TableHead>
              <TableHead className="py-2">{t('Supplier')}</TableHead>
              <TableHead className="py-2 text-right">{t('Stock')}</TableHead>
              <TableHead className="py-2">{t('Status')}</TableHead>
              <TableHead className="py-2 text-right">{t('Stock Value')}</TableHead>
              <TableHead className="w-[60px] py-2">{t('Actions')}</TableHead>
            </TableRow>
            {pageAllSelected && !allFilteredSelected && total > pageIds.length && (
              <TableRow className="bg-muted hover:bg-muted">
                <TableHead colSpan={12 + parameterColumns.length} className="py-1.5 text-center text-xs font-normal text-muted-foreground">
                  {t('All {count} parts on this page are selected.', { count: pageIds.length })}{' '}
                  <Button
                    type="button"
                    variant="link"
                    onClick={selectAllMatching}
                    className="h-auto p-0 underline underline-offset-2 hover:no-underline"
                  >
                    {t('Select all {count} parts matching filters', { count: total })}
                  </Button>
                </TableHead>
              </TableRow>
            )}
          </TableHeader>
          <TableBody>
            {parts.map((part) => {
              const stockKey = stockStatusKey(part.total_quantity, part.min_stock_threshold)
              const stockValue = part.unit_price != null ? part.unit_price * part.total_quantity : null
              return (
                <TableRow key={part.id} data-state={selected.includes(part.id) ? 'selected' : undefined}>
                  <TableCell className="py-2.5" onClick={(e) => e.stopPropagation()}>
                    <Checkbox
                      checked={selected.includes(part.id)}
                      onCheckedChange={() => toggleRow(part.id)}
                      aria-label={`Select ${part.name}`}
                    />
                  </TableCell>
                  <TableCell className="py-2.5">
                    <div className="flex items-center gap-3">
                      <PartThumbnail url={part.thumbnail_url} />
                      <div className="min-w-0">
                        <Button
                          type="button"
                          variant="link"
                          onClick={() => onShowPart(part.id)}
                          title={part.mpn || part.sku || part.name}
                          className="block h-auto max-w-[240px] truncate p-0 text-left font-mono font-semibold text-foreground"
                        >
                          {part.mpn || part.sku || part.name}
                        </Button>
                        <div className="max-w-[240px] truncate text-xs text-muted-foreground" title={part.name}>
                          {part.name}
                        </div>
                      </div>
                    </div>
                  </TableCell>
                  <TableCell className="py-2.5 font-mono text-sm text-muted-foreground">
                    {part.ipn || '-'}
                  </TableCell>
                  <TableCell className="py-2.5">
                    {part.category ? (
                      <span className="inline-flex items-center gap-1.5 text-sm">
                        <span
                          className="size-1.5 shrink-0 rounded-sm"
                          style={{ backgroundColor: part.category.color || 'var(--muted-foreground)' }}
                        />
                        {part.category.name}
                      </span>
                    ) : (
                      <span className="text-muted-foreground">-</span>
                    )}
                  </TableCell>
                  <TableCell className="py-2.5 font-mono text-sm font-medium">
                    {part.value || <span className="font-sans text-muted-foreground">-</span>}
                  </TableCell>
                  {parameterColumns.map((column) => (
                    <TableCell key={`param-${column.id}`} className="py-2.5 font-mono text-sm whitespace-nowrap">
                      {part.parameters.find((parameter) => parameter.id === column.id)?.display ?? <span className="font-sans text-muted-foreground">-</span>}
                    </TableCell>
                  ))}
                  <TableCell className="py-2.5 font-mono text-sm text-muted-foreground">
                    {part.package_type || '-'}
                  </TableCell>
                  <TableCell className="py-2.5 font-mono text-sm text-muted-foreground">
                    {locationLabel(part.location_names)}
                  </TableCell>
                  <TableCell className="py-2.5 text-sm text-muted-foreground">
                    {part.supplier_name || '-'}
                  </TableCell>
                  <TableCell className="py-2.5 text-right font-mono text-sm font-semibold">
                    {part.total_quantity}
                  </TableCell>
                  <TableCell className="py-2.5">
                    <div className="flex flex-col items-start gap-1">
                      <span className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${STOCK_STATUS_META[stockKey].className}`}>
                        {STOCK_STATUS_META[stockKey].label}
                      </span>
                      {part.status !== 'active' && (
                        <span className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${LIFECYCLE_META[part.status].className}`}>
                          {LIFECYCLE_META[part.status].label}
                        </span>
                      )}
                    </div>
                  </TableCell>
                  <TableCell className="py-2.5 text-right font-mono text-sm text-muted-foreground">
                    {stockValue != null ? stockValue.toFixed(2) : '-'}
                  </TableCell>
                  <TableCell className="py-2.5">
                    {canWrite && (
                      <Button variant="ghost" size="icon" onClick={() => onEditPart(part.id)} aria-label={t('Edit part')}>
                        <Pencil className="size-4" />
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>

        {pageCount > 1 && (
          <div className="sticky bottom-0 flex items-center justify-between border-t bg-background px-5 py-2.5 text-sm text-muted-foreground">
            <span>
              {t('{from}–{to} of {total} · Page {page}/{pages}', { from: (page - 1) * pageSize + 1, to: Math.min(page * pageSize, total), total, page, pages: pageCount })}
            </span>
            <div className="flex gap-2">
              <Button variant="outline" size="sm" disabled={page <= 1} onClick={() => onPageChange(page - 1)}>
                <ChevronLeft className="size-4" />
                {t('Previous')}
              </Button>
              <Button variant="outline" size="sm" disabled={page >= pageCount} onClick={() => onPageChange(page + 1)}>
                {t('Next')}
                <ChevronRight className="size-4" />
              </Button>
            </div>
          </div>
        )}
      </>
    )}
    </div>
  )
}
