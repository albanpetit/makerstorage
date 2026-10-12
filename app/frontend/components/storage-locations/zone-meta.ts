import {
  DoorOpen,
  Archive,
  Layers,
  Wrench,
  ArchiveRestore,
  Package,
  type LucideIcon,
} from 'lucide-react'

import type { RecentMovement } from './types'

export const LOCATION_TYPES = ['room', 'cabinet', 'shelf', 'bench', 'drawer', 'box'] as const

export const TYPE_META: Record<string, { label: string; icon: LucideIcon; className: string }> = {
  room: { label: 'Room', icon: DoorOpen, className: 'bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-400' },
  cabinet: { label: 'Cabinet', icon: Archive, className: 'bg-purple-100 text-purple-700 dark:bg-purple-950 dark:text-purple-400' },
  shelf: { label: 'Shelf', icon: Layers, className: 'bg-cyan-100 text-cyan-700 dark:bg-cyan-950 dark:text-cyan-400' },
  bench: { label: 'Bench', icon: Wrench, className: 'bg-pink-100 text-pink-700 dark:bg-pink-950 dark:text-pink-400' },
  drawer: { label: 'Drawer', icon: ArchiveRestore, className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
  box: { label: 'Box', icon: Package, className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
}

export const MOVEMENT_META: Record<RecentMovement['movement_type'], { label: string; className: string }> = {
  in: { label: 'In', className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
  out: { label: 'Out', className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
  adjustment: { label: 'Adjustment', className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
}

export function typeMeta(type: string) {
  return TYPE_META[type] || TYPE_META.box
}

export function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, { day: '2-digit', month: '2-digit', year: 'numeric' })
}
