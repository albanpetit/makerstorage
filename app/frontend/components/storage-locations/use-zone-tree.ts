import { useMemo, useState } from 'react'

import type { PartStorageEntry, StorageLocationRecord } from './types'

export interface TreeRow {
  location: StorageLocationRecord
  depth: number
  hasChildren: boolean
  refCount: number
}

// Derived views of the flat zone list: parent/child lookups, per-zone
// aggregate counts, the searchable + collapsible tree rows, and the indented
// option lists used by the zone pickers.
export function useZoneTree(storage_locations: StorageLocationRecord[], part_storages: PartStorageEntry[], query: string) {
  const [expanded, setExpanded] = useState<Set<number>>(
    () => new Set(storage_locations.filter((z) => storage_locations.some((c) => c.parent_id === z.id)).map((z) => z.id))
  )

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

  // Flat, indented list of every zone (for the bulk "move to" picker).
  function allZoneOptions() {
    const options: { id: number; label: string }[] = []
    const walk = (parentId: number | null, depth: number) => {
      (childrenByParent.get(parentId) || []).forEach((z) => {
        options.push({ id: z.id, label: `${'— '.repeat(depth)}${z.name}` })
        walk(z.id, depth + 1)
      })
    }
    walk(null, 0)
    return options
  }

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

  return {
    byId,
    childrenByParent,
    partStoragesByLocation,
    aggCounts,
    subtreeIds,
    pathOf,
    visibleIds,
    treeRows,
    expanded,
    setExpanded,
    toggleExpand,
    expandAll,
    collapseAll,
    parentOptions,
    allZoneOptions,
  }
}

export type ZoneTree = ReturnType<typeof useZoneTree>
