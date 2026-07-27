import * as React from 'react'
import { Popover as PopoverPrimitive } from 'radix-ui'
import {
  ChevronRight,
  ChevronsUpDown,
  DoorOpen,
  Archive,
  Layers,
  Wrench,
  ArchiveRestore,
  Package,
  type LucideIcon,
} from 'lucide-react'

import { cn } from '@/lib/utils'

export interface ZoneNode {
  id: number
  name: string
  location_type: string
  code: string | null
  parent_id: number | null
}

// Same icon vocabulary as the Storage Zones page.
const TYPE_ICON: Record<string, LucideIcon> = {
  room: DoorOpen,
  cabinet: Archive,
  shelf: Layers,
  bench: Wrench,
  drawer: ArchiveRestore,
  box: Package,
}

interface StorageZoneTreePickerProps {
  locations: ZoneNode[]
  value: number | null
  onChange: (id: number) => void
  placeholder?: string
  className?: string
  disabled?: boolean
}

// A collapsible storage-zone tree in a popover — the same hierarchy shown on the
// Storage Zones page, for picking a target zone. Built on the Radix Popover
// primitive like the Combobox so it stays dependency-light.
export function StorageZoneTreePicker({
  locations,
  value,
  onChange,
  placeholder = 'Select a zone',
  className,
  disabled,
}: StorageZoneTreePickerProps) {
  const [open, setOpen] = React.useState(false)
  const [expanded, setExpanded] = React.useState<Set<number>>(new Set())

  const childrenByParent = React.useMemo(() => {
    const map = new Map<number | null, ZoneNode[]>()
    for (const zone of locations) {
      const key = zone.parent_id
      if (!map.has(key)) map.set(key, [])
      map.get(key)!.push(zone)
    }
    for (const arr of map.values()) arr.sort((a, b) => a.name.localeCompare(b.name))
    return map
  }, [locations])

  const byId = React.useMemo(() => new Map(locations.map((z) => [z.id, z])), [locations])
  const selected = value != null ? byId.get(value) : undefined

  // Expand the selected zone's ancestors when opening so it's visible.
  React.useEffect(() => {
    if (!open || value == null) return
    const ancestors = new Set<number>()
    let current = byId.get(value)
    while (current?.parent_id != null) {
      ancestors.add(current.parent_id)
      current = byId.get(current.parent_id)
    }
    if (ancestors.size) setExpanded((prev) => new Set([...prev, ...ancestors]))
  }, [open, value, byId])

  const toggle = (id: number) =>
    setExpanded((prev) => {
      const next = new Set(prev)
      next.has(id) ? next.delete(id) : next.add(id)
      return next
    })

  const renderNodes = (parentId: number | null, depth: number): React.ReactNode =>
    (childrenByParent.get(parentId) || []).map((zone) => {
      const hasChildren = (childrenByParent.get(zone.id) || []).length > 0
      const isOpen = expanded.has(zone.id)
      const Icon = TYPE_ICON[zone.location_type] ?? Package
      return (
        <div key={zone.id}>
          <div className="flex items-center" style={{ paddingLeft: `${depth * 14}px` }}>
            <button
              type="button"
              tabIndex={-1}
              aria-label={hasChildren ? (isOpen ? 'Collapse' : 'Expand') : undefined}
              onClick={() => hasChildren && toggle(zone.id)}
              className="flex size-5 shrink-0 items-center justify-center"
            >
              {hasChildren && <ChevronRight className={cn('size-3.5 transition-transform', isOpen && 'rotate-90')} />}
            </button>
            <button
              type="button"
              onClick={() => {
                onChange(zone.id)
                setOpen(false)
              }}
              className={cn(
                'flex flex-1 items-center gap-2 rounded-sm px-2 py-1.5 text-left text-sm outline-none hover:bg-accent hover:text-accent-foreground',
                zone.id === value && 'bg-accent/60 font-medium'
              )}
            >
              <Icon className="size-4 shrink-0 text-muted-foreground" />
              <span className="line-clamp-1">{zone.name}</span>
              {zone.code && <span className="ml-auto shrink-0 text-xs text-muted-foreground">{zone.code}</span>}
            </button>
          </div>
          {hasChildren && isOpen && renderNodes(zone.id, depth + 1)}
        </div>
      )
    })

  return (
    <PopoverPrimitive.Root open={open} onOpenChange={setOpen}>
      <PopoverPrimitive.Trigger
        disabled={disabled}
        className={cn(
          'border-input focus-visible:border-ring focus-visible:ring-ring/50 dark:bg-input/30 dark:hover:bg-input/50 flex h-9 items-center justify-between gap-2 rounded-md border bg-transparent px-3 py-2 text-sm whitespace-nowrap shadow-xs transition-[color,box-shadow] outline-none focus-visible:ring-[3px] disabled:cursor-not-allowed disabled:opacity-50',
          !selected && 'text-muted-foreground',
          className
        )}
      >
        <span className="line-clamp-1 text-left">{selected ? selected.name : placeholder}</span>
        <ChevronsUpDown className="size-4 shrink-0 opacity-50" />
      </PopoverPrimitive.Trigger>

      <PopoverPrimitive.Portal>
        <PopoverPrimitive.Content
          align="start"
          sideOffset={4}
          className={cn(
            'bg-popover text-popover-foreground z-50 w-[var(--radix-popover-trigger-width)] min-w-[15rem] overflow-hidden rounded-md border shadow-md',
            'data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95'
          )}
        >
          <div className="max-h-72 overflow-y-auto p-1">
            {locations.length === 0 ? (
              <div className="text-muted-foreground py-6 text-center text-sm">No storage zones yet.</div>
            ) : (
              renderNodes(null, 0)
            )}
          </div>
        </PopoverPrimitive.Content>
      </PopoverPrimitive.Portal>
    </PopoverPrimitive.Root>
  )
}
