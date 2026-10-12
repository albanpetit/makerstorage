import { useMemo, useState } from 'react'

import { SORT_FNS, STOCK_STATUS_META, stockStatusKey, type SortKey } from './part-meta'
import type { Part } from './types'

// Client-side search, category chip, facet and sort state for the Parts page.
// Facet counts are computed after search + category so each chip shows how
// many parts it would leave.
export function usePartFilters(parts: Part[], initialQuery: string) {
  const [query, setQuery] = useState(initialQuery || '')
  const [categoryId, setCategoryId] = useState<number | 'all'>('all')
  const [fStatus, setFStatus] = useState<string[]>([])
  const [fPackage, setFPackage] = useState<string[]>([])
  const [fFootprint, setFFootprint] = useState<string[]>([])
  const [fSupplier, setFSupplier] = useState<string[]>([])
  const [sortKey, setSortKey] = useState<SortKey>('ref')

  const categoryChips = useMemo(() => {
    const counts = new Map<number, { name: string; count: number }>()
    for (const part of parts) {
      if (!part.category) continue
      const existing = counts.get(part.category.id)
      if (existing) {
        existing.count += 1
      } else {
        counts.set(part.category.id, { name: part.category.name, count: 1 })
      }
    }
    return Array.from(counts.entries())
      .map(([id, { name, count }]) => ({ id, name, count }))
      .sort((a, b) => a.name.localeCompare(b.name))
  }, [parts])

  const afterSearchAndCategory = useMemo(() => {
    let result = parts
    if (categoryId !== 'all') {
      result = result.filter((part) => part.category?.id === categoryId)
    }
    const q = query.trim().toLowerCase()
    if (q) {
      result = result.filter((part) => {
        const haystack = [
          part.name, part.mpn, part.sku, part.ipn, part.manufacturer, part.value,
          part.category?.name, part.footprint?.name, ...part.location_names,
        ].filter(Boolean).join(' ').toLowerCase()
        return haystack.includes(q)
      })
    }
    return result
  }, [parts, categoryId, query])

  const statusOptions = useMemo(() => {
    const counts = new Map<string, number>()
    for (const part of afterSearchAndCategory) {
      const key = stockStatusKey(part.total_quantity, part.min_stock_threshold)
      counts.set(key, (counts.get(key) || 0) + 1)
    }
    return (Object.keys(STOCK_STATUS_META) as (keyof typeof STOCK_STATUS_META)[])
      .filter((key) => counts.has(key))
      .map((key) => ({ value: key, label: STOCK_STATUS_META[key].label, count: counts.get(key)! }))
  }, [afterSearchAndCategory])

  const packageOptions = useMemo(() => {
    const counts = new Map<string, number>()
    for (const part of afterSearchAndCategory) {
      if (!part.package_type) continue
      counts.set(part.package_type, (counts.get(part.package_type) || 0) + 1)
    }
    return Array.from(counts.entries()).sort((a, b) => a[0].localeCompare(b[0]))
  }, [afterSearchAndCategory])

  const footprintOptions = useMemo(() => {
    const counts = new Map<string, number>()
    for (const part of afterSearchAndCategory) {
      if (!part.footprint) continue
      counts.set(part.footprint.name, (counts.get(part.footprint.name) || 0) + 1)
    }
    return Array.from(counts.entries()).sort((a, b) => a[0].localeCompare(b[0]))
  }, [afterSearchAndCategory])

  const supplierOptions = useMemo(() => {
    const counts = new Map<string, number>()
    for (const part of afterSearchAndCategory) {
      if (!part.supplier_name) continue
      counts.set(part.supplier_name, (counts.get(part.supplier_name) || 0) + 1)
    }
    return Array.from(counts.entries()).sort((a, b) => a[0].localeCompare(b[0]))
  }, [afterSearchAndCategory])

  const filtered = useMemo(() => {
    let result = afterSearchAndCategory
    if (fStatus.length > 0) {
      result = result.filter((part) => fStatus.includes(stockStatusKey(part.total_quantity, part.min_stock_threshold)))
    }
    if (fPackage.length > 0) {
      result = result.filter((part) => part.package_type != null && fPackage.includes(part.package_type))
    }
    if (fFootprint.length > 0) {
      result = result.filter((part) => part.footprint != null && fFootprint.includes(part.footprint.name))
    }
    if (fSupplier.length > 0) {
      result = result.filter((part) => part.supplier_name != null && fSupplier.includes(part.supplier_name))
    }
    return result
  }, [afterSearchAndCategory, fStatus, fPackage, fFootprint, fSupplier])

  const sorted = useMemo(() => [ ...filtered ].sort(SORT_FNS[sortKey]), [filtered, sortKey])

  const toggleFacet = (list: string[], setList: (v: string[]) => void, value: string) => {
    setList(list.includes(value) ? list.filter((v) => v !== value) : [ ...list, value ])
  }

  const activePills = useMemo(() => {
    const pills: { key: string; label: string; remove: () => void }[] = []
    if (categoryId !== 'all') {
      const chip = categoryChips.find((c) => c.id === categoryId)
      pills.push({ key: 'cat', label: `Category: ${chip?.name || categoryId}`, remove: () => setCategoryId('all') })
    }
    if (query.trim()) {
      pills.push({ key: 'q', label: `Search: "${query.trim()}"`, remove: () => setQuery('') })
    }
    fStatus.forEach((v) => pills.push({
      key: `status-${v}`,
      label: STOCK_STATUS_META[v as keyof typeof STOCK_STATUS_META].label,
      remove: () => setFStatus(fStatus.filter((x) => x !== v)),
    }))
    fPackage.forEach((v) => pills.push({
      key: `pkg-${v}`, label: `Package: ${v}`, remove: () => setFPackage(fPackage.filter((x) => x !== v)),
    }))
    fFootprint.forEach((v) => pills.push({
      key: `fp-${v}`, label: `Footprint: ${v}`, remove: () => setFFootprint(fFootprint.filter((x) => x !== v)),
    }))
    fSupplier.forEach((v) => pills.push({
      key: `sup-${v}`, label: v, remove: () => setFSupplier(fSupplier.filter((x) => x !== v)),
    }))
    return pills
  }, [categoryId, query, fStatus, fPackage, fFootprint, fSupplier, categoryChips])

  const clearAllFilters = () => {
    setCategoryId('all')
    setQuery('')
    setFStatus([])
    setFPackage([])
    setFFootprint([])
    setFSupplier([])
  }

  return {
    query, setQuery,
    categoryId, setCategoryId,
    fStatus, setFStatus,
    fPackage, setFPackage,
    fFootprint, setFFootprint,
    fSupplier, setFSupplier,
    sortKey, setSortKey,
    categoryChips,
    statusOptions,
    packageOptions,
    footprintOptions,
    supplierOptions,
    filtered,
    sorted,
    toggleFacet,
    activePills,
    clearAllFilters,
  }
}

export type PartFilters = ReturnType<typeof usePartFilters>
