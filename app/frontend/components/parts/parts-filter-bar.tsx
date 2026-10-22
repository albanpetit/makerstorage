import { useState } from 'react'
import { SlidersHorizontal, X } from 'lucide-react'

import { Button } from '@/components/ui/button'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

import { ParameterFilterDialog } from './parameter-filter-dialog'
import { SORT_OPTIONS } from './part-meta'
import type { SortKey } from './types'
import type { PartFilters } from './use-part-filters'
import { t } from '@/lib/i18n'

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

interface PartsFilterBarProps {
  filters: PartFilters
  totalCount: number
}

// Category chips, sort select, facet groups and active-filter pills above the
// parts table. Counts come from the server (PartsIndexQuery#facets).
export function PartsFilterBar({ filters, totalCount }: PartsFilterBarProps) {
  const { filters: current, facets, setCategory, setSort, toggleFacet, setParameterFilter, activePills, clearAllFilters } = filters
  const categoryChips = facets.categories
  const categoryId = current.category
  const [parameterId, setParameterId] = useState<number | null>(null)
  const parameterFacet = facets.parameters.find((facet) => facet.id === parameterId) ?? null

  return (
    <div className="flex shrink-0 flex-col gap-2 border-b bg-background px-5 py-3">
      {/* Category filter chips + sort */}
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex flex-1 flex-wrap items-center gap-2">
          {categoryChips.length > 0 && (
            <>
              <Button
                variant={categoryId == null ? 'default' : 'outline'}
                size="sm"
                onClick={() => setCategory(null)}
                className={`h-8 gap-1.5 rounded-full border px-3 shadow-none ${categoryId == null ? 'border-primary' : ''}`}
              >
                {t('All')}
                <span className="text-xs opacity-75">{totalCount}</span>
              </Button>
              {categoryChips.map((chip) => (
                <Button
                  key={chip.id}
                  variant={categoryId === chip.id ? 'default' : 'outline'}
                  size="sm"
                  onClick={() => setCategory(chip.id)}
                  className={`h-8 gap-1.5 rounded-full border px-3 shadow-none ${categoryId === chip.id ? 'border-primary' : ''}`}
                >
                  {chip.name}
                  <span className="text-xs opacity-75">{chip.count}</span>
                </Button>
              ))}
            </>
          )}
        </div>
        <Select value={current.sort} onValueChange={(value) => setSort(value as SortKey)}>
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
        <FacetGroup label={t('Status')} options={facets.status} active={current.status} onToggle={(v) => toggleFacet('status', v)} />
        <FacetGroup label={t('Package')} options={facets.package} active={current.package} onToggle={(v) => toggleFacet('package', v)} />
        <FacetGroup label={t('Footprint')} options={facets.footprint} active={current.footprint} onToggle={(v) => toggleFacet('footprint', v)} />
        <FacetGroup label={t('Supplier')} options={facets.supplier} active={current.supplier} onToggle={(v) => toggleFacet('supplier', v)} />
        {facets.parameters.length > 0 && (
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="text-xs font-medium text-muted-foreground">{t('Parameters')}</span>
            {facets.parameters.map((facet) => {
              const active = current.parameters.some((filter) => filter.id === facet.id)
              return (
                <Button
                  key={facet.id}
                  variant={active ? 'default' : 'outline'}
                  size="sm"
                  onClick={() => setParameterId(facet.id)}
                  className={`h-7 gap-1 rounded-md border px-2 text-xs shadow-none ${active ? 'border-primary' : ''}`}
                >
                  <SlidersHorizontal className="size-3" />
                  {facet.name} <span className="opacity-75">({facet.count})</span>
                </Button>
              )
            })}
          </div>
        )}
      </div>

      <ParameterFilterDialog
        facet={parameterFacet}
        current={current.parameters.find((filter) => filter.id === parameterId)}
        onOpenChange={(open) => !open && setParameterId(null)}
        onApply={(filter) => {
          if (parameterId != null) setParameterFilter(parameterId, filter)
          setParameterId(null)
        }}
      />

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
                aria-label={t('Remove filter {name}', { name: pill.label })}
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
            {t('Clear all')}
          </Button>
        </div>
      )}
    </div>
  )
}
