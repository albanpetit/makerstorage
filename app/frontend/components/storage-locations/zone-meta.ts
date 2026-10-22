import {
  DoorOpen,
  Archive,
  Layers,
  Wrench,
  ArchiveRestore,
  Package,
  ShoppingBag,
  type LucideIcon,
} from 'lucide-react'

import type { RecentMovement } from './types'
import { t, intlLocale } from '@/lib/i18n'

export const LOCATION_TYPES = ['room', 'cabinet', 'shelf', 'bench', 'drawer', 'box', 'bag'] as const

export const TYPE_META: Record<string, { label: string; icon: LucideIcon; className: string }> = {
  room: { get label() { return t('Room') }, icon: DoorOpen, className: 'bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-400' },
  cabinet: { get label() { return t('Cabinet') }, icon: Archive, className: 'bg-purple-100 text-purple-700 dark:bg-purple-950 dark:text-purple-400' },
  shelf: { get label() { return t('Shelf') }, icon: Layers, className: 'bg-cyan-100 text-cyan-700 dark:bg-cyan-950 dark:text-cyan-400' },
  bench: { get label() { return t('Bench') }, icon: Wrench, className: 'bg-pink-100 text-pink-700 dark:bg-pink-950 dark:text-pink-400' },
  drawer: { get label() { return t('Drawer') }, icon: ArchiveRestore, className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
  box: { get label() { return t('Box') }, icon: Package, className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
  bag: { get label() { return t('Bag') }, icon: ShoppingBag, className: 'bg-orange-100 text-orange-700 dark:bg-orange-950 dark:text-orange-400' },
}

export const MOVEMENT_META: Record<RecentMovement['movement_type'], { label: string; className: string }> = {
  in: { get label() { return t('In') }, className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
  out: { get label() { return t('Out') }, className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
  adjustment: { get label() { return t('Adjustment') }, className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
}

export function typeMeta(type: string) {
  return TYPE_META[type] || TYPE_META.box
}

export function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(intlLocale(), { day: '2-digit', month: '2-digit', year: 'numeric' })
}
