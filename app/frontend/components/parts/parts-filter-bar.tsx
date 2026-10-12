import { X } from 'lucide-react'

import { Button } from '@/components/ui/button'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

import { SORT_OPTIONS, type SortKey } from './part-meta'
import type { PartFilters } from './use-part-filters'

interface FacetGroupProps {
  label: string
  options: { value: string; label: string; count: number }[]
  active: string[]
  onToggle: (value: string) => void
}

function FacetGroup({ label, options, active, onToggle }: FacetGroupProps) {
  if (options.length === 0) return null

  return (
    <div className="flex flex-wrap items-center gap-1.5">
      <span className="text-xs font-medium text-muted-foreground">{label}</span>
      {options.map((opt) => (
        <Button
          key={opt.value}
          variant={active.includes(opt.value) ? 'default' : 'outline'}
          size="sm"
          onClick={() => onToggle(opt.value)}
          className={`h-7 gap-1 rounded-md border px-2 text-xs shadow-none ${active.includes(opt.value) ? 'border-primary' : ''}`}
        >
          {opt.label} <span className="opacity-75">({opt.count})</span>
        </Button>
      ))}
    </div>
  )
}

const countedOptions = (entries: [string, number][]) =>
  entries.map(([value, count]) => ({ value, label: value, count }))

interface PartsFilterBarProps {
  filters: PartFilters
  totalCount: number
  // Called whenever a chip or facet changes the result set, so the table can
  // go back to its first page.
  onFilterChange: () => void
}

// Category chips, sort select, facet groups and active-filter pills above the
// parts table.
export function PartsFilterBar({ filters, totalCount, onFilterChange }: PartsFilterBarProps) {
  const {
    categoryChips, categoryId, setCategoryId, sortKey, setSortKey,
    statusOptions, packageOptions, footprintOptions, supplierOptions,
    fStatus, setFStatus, fPackage, setFPackage, fFootprint, setFFootprint, fSupplier, setFSupplier,
    toggleFacet, activePills, clearAllFilters,
  } = filters

  const facet = (list: string[], setList: (v: string[]) => void) => (value: string) => {
    toggleFacet(list, setList, value)
    onFilterChange()
  }

  return (
    <div className="flex shrink-0 flex-col gap-2 border-b bg-background px-5 py-3">
      {/* Category filter chips + sort */}
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex flex-1 flex-wrap items-center gap-2">
          {categoryChips.length > 0 && (
            <>
              <Button
                variant={categoryId === 'all' ? 'default' : 'outline'}
                size="sm"
                onClick={() => { setCategoryId('all'); onFilterChange() }}
                className={`h-8 gap-1.5 rounded-full border px-3 shadow-none ${categoryId === 'all' ? 'border-primary' : ''}`}
              >
                All
                <span className="text-xs opacity-75">{totalCount}</span>
              </Button>
              {categoryChips.map((chip) => (
                <Button
                  key={chip.id}
                  variant={categoryId === chip.id ? 'default' : 'outline'}
                  size="sm"
                  onClick={() => { setCategoryId(chip.id); onFilterChange() }}
                  className={`h-8 gap-1.5 rounded-full border px-3 shadow-none ${categoryId === chip.id ? 'border-primary' : ''}`}
                >
                  {chip.name}
                  <span className="text-xs opacity-75">{chip.count}</span>
                </Button>
              ))}
            </>
          )}
        </div>
        <Select value={sortKey} onValueChange={(value) => setSortKey(value as SortKey)}>
          <SelectTrigger className="h-8 w-[190px] text-xs" size="sm">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {SORT_OPTIONS.map((option) => (
              <SelectItem key={option.value} value={option.value}>{option.label}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {/* Facet groups */}
      <div className="flex flex-col gap-2">
        <FacetGroup label="Status" options={statusOptions} active={fStatus} onToggle={facet(fStatus, setFStatus)} />
        <FacetGroup label="Package" options={countedOptions(packageOptions)} active={fPackage} onToggle={facet(fPackage, setFPackage)} />
        <FacetGroup label="Footprint" options={countedOptions(footprintOptions)} active={fFootprint} onToggle={facet(fFootprint, setFFootprint)} />
        <FacetGroup label="Supplier" options={countedOptions(supplierOptions)} active={fSupplier} onToggle={facet(fSupplier, setFSupplier)} />
      </div>

      {/* Active filter pills */}
      {activePills.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          {activePills.map((pill) => (
            <span
              key={pill.key}
              className="inline-flex items-center gap-1 rounded-full bg-muted px-2.5 py-1 text-xs font-medium"
            >
              {pill.label}
              <Button
                variant="ghost"
                size="icon"
                onClick={pill.remove}
                aria-label={`Remove filter ${pill.label}`}
                className="size-4 rounded-full text-muted-foreground hover:bg-transparent hover:text-foreground"
              >
                <X className="size-3" />
              </Button>
            </span>
          ))}
          <Button
            variant="link"
            size="sm"
            onClick={clearAllFilters}
            className="h-auto px-0 text-xs text-muted-foreground underline underline-offset-2 hover:text-foreground"
          >
            Clear all
          </Button>
        </div>
      )}
    </div>
  )
}
