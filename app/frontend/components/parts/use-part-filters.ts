import { useEffect, useRef, useState } from 'react'
import { router } from '@inertiajs/react'

import type { ParameterFilter, PartListFacets, PartListFilters } from './types'
import { t } from '@/lib/i18n'

type FacetKey = 'status' | 'package' | 'footprint' | 'supplier'

// Query string for a list visit: empty filters, the default sort and the
// first page are left out so a plain /parts URL stays plain.
function toParams(filters: PartListFilters, page: number) {
  return {
    ...(filters.search ? { search: filters.search } : {}),
    ...(filters.category != null ? { category: filters.category } : {}),
    ...(filters.status.length ? { status: filters.status } : {}),
    ...(filters.package.length ? { package: filters.package } : {}),
    ...(filters.footprint.length ? { footprint: filters.footprint } : {}),
    ...(filters.supplier.length ? { supplier: filters.supplier } : {}),
    ...(filters.parameters.length ? { param: parameterParams(filters.parameters) } : {}),
    ...(filters.sort !== 'ref' ? { sort: filters.sort } : {}),
    ...(page > 1 ? { page } : {}),
  }
}

// `param[<id>][min|max]` / `param[<id>][values][]`, as PartsIndexQuery reads them.
function parameterParams(filters: ParameterFilter[]) {
  return Object.fromEntries(
    filters.map((filter) => [
      filter.id,
      filter.value_type === 'text'
        ? { values: filter.values }
        : { ...(filter.min ? { min: filter.min } : {}), ...(filter.max ? { max: filter.max } : {}) },
    ]),
  )
}

// What a filter pill says: "Resistance: 1 kΩ – 47 kΩ", "Power rating ≥ 250 mW".
function parameterLabel(filter: ParameterFilter) {
  if (filter.value_type === 'text') return `${filter.name}: ${filter.values.join(', ')}`
  const min = filter.min_display ?? filter.min
  const max = filter.max_display ?? filter.max
  const range = min && max ? `: ${min} – ${max}` : min ? ` ≥ ${min}` : ` ≤ ${max}`
  return `${filter.name}${range}${filter.invalid ? ' (not understood)' : ''}`
}

// The inventory list's search, category, facet and sort state. Filtering runs
// on the server (PartsIndexQuery): every change is a visit to /parts with the
// new query string, which also returns to the first page. The search box
// waits for a pause in typing before it visits.
export function usePartFilters(filters: PartListFilters, facets: PartListFacets) {
  const [query, setQuery] = useState(filters.search)
  const queryRef = useRef(query)
  queryRef.current = query
  // The search last sent to the server, so the debounce doesn't repeat a
  // visit another control already made.
  const sentSearch = useRef(filters.search)

  const visit = (changes: Partial<PartListFilters>, page = 1, replace = false) => {
    const next = { ...filters, search: queryRef.current.trim(), ...changes }
    sentSearch.current = next.search
    router.get('/parts', toParams(next, page), { preserveState: true, preserveScroll: true, replace })
  }

  useEffect(() => {
    if (query.trim() === sentSearch.current) return
    const timer = setTimeout(() => visit({ search: query.trim() }, 1, true), 300)
    return () => clearTimeout(timer)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query])

  const toggleFacet = (key: FacetKey, value: string) => {
    const list = filters[key]
    visit({ [key]: list.includes(value) ? list.filter((v) => v !== value) : [ ...list, value ] })
  }

  // Replaces (or with null removes) the filter on one parameter.
  const setParameterFilter = (id: number, filter: ParameterFilter | null) => {
    const others = filters.parameters.filter((existing) => existing.id !== id)
    visit({ parameters: filter ? [ ...others, filter ] : others })
  }

  const setCategory = (category: number | null) => visit({ category })
  const setSort = (sort: PartListFilters['sort']) => visit({ sort })
  const goToPage = (page: number) => visit({}, page)

  const clearSearch = () => {
    setQuery('')
    queryRef.current = ''
    visit({ search: '' })
  }

  const clearAllFilters = () => {
    setQuery('')
    queryRef.current = ''
    visit({ search: '', category: null, status: [], package: [], footprint: [], supplier: [], parameters: [] })
  }

  const facetLabel = (key: FacetKey, value: string) =>
    facets[key].find((option) => option.value === value)?.label ?? value

  const activePills: { key: string; label: string; remove: () => void }[] = []
  if (filters.category != null) {
    const chip = facets.categories.find((c) => c.id === filters.category)
    activePills.push({ key: 'cat', label: t('Category: {name}', { name: chip?.name || filters.category }), remove: () => setCategory(null) })
  }
  if (filters.search) {
    activePills.push({ key: 'q', label: t('Search: “{query}”', { query: filters.search }), remove: clearSearch })
  }
  filters.status.forEach((v) => activePills.push({ key: `status-${v}`, label: facetLabel('status', v), remove: () => toggleFacet('status', v) }))
  filters.package.forEach((v) => activePills.push({ key: `pkg-${v}`, label: t('Package: {name}', { name: v }), remove: () => toggleFacet('package', v) }))
  filters.footprint.forEach((v) => activePills.push({ key: `fp-${v}`, label: t('Footprint: {name}', { name: v }), remove: () => toggleFacet('footprint', v) }))
  filters.supplier.forEach((v) => activePills.push({ key: `sup-${v}`, label: v, remove: () => toggleFacet('supplier', v) }))
  filters.parameters.forEach((filter) =>
    activePills.push({ key: `param-${filter.id}`, label: parameterLabel(filter), remove: () => setParameterFilter(filter.id, null) }))

  return {
    filters,
    facets,
    query,
    setQuery,
    setCategory,
    setSort,
    toggleFacet,
    setParameterFilter,
    goToPage,
    activePills,
    clearAllFilters,
  }
}

export type PartFilters = ReturnType<typeof usePartFilters>
