import { Head, router } from '@inertiajs/react'
import { useMemo, useRef, useState } from 'react'
import { toast } from 'sonner'
import {
  Plus, Search, Package, Pencil, Download, Upload,
  ChevronLeft, ChevronRight, Move, Tag, Trash2, X,
  Layers, CircleDot, Tags, Truck,
} from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { html, printDocument } from '@/lib/print-document'
import { SidebarTrigger } from '@/components/ui/sidebar'
import { usePermissions } from '@/hooks/use-permissions'
import { ReadOnlyBadge } from '@/components/read-only-badge'
import { FlashMessages } from '@/components/flash-messages'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Checkbox } from '@/components/ui/checkbox'
import { Label } from '@/components/ui/label'
import { AddPartDialog } from '@/components/add-part-dialog'
import { EditPartDialog } from '@/components/edit-part-dialog'
import { PartDetailSheet } from '@/components/part-detail-sheet'
import { TagPicker } from '@/components/tag-picker'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

const PAGE_SIZE = 20

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

interface Part {
  id: number
  name: string
  mpn: string | null
  sku: string | null
  ipn: string | null
  barcode: string | null
  manufacturer: string | null
  description: string | null
  value: string | null
  package_type: string | null
  status: 'active' | 'discontinued' | 'obsolete'
  tag_names: string[]
  thumbnail_url: string | null
  total_quantity: number
  min_stock_threshold: number
  unit_price: number | null
  location_names: string[]
  supplier_name: string | null
  category: {
    id: number
    name: string
    color: string | null
  } | null
  footprint: {
    id: number
    name: string
  } | null
}

interface Category {
  id: number
  name: string
}

interface Footprint {
  id: number
  name: string
  mounting_type: string | null
}

interface Supplier {
  id: number
  name: string
}

interface Tag {
  id: number
  name: string
  color: string | null
}

interface StorageLocationOption {
  id: number
  name: string
}

interface PartsIndexProps {
  parts: Part[]
  initial_query: string
  categories: Category[]
  footprints: Footprint[]
  suppliers: Supplier[]
  tags: Tag[]
  storage_locations: StorageLocationOption[]
  supplier_lookup_enabled: boolean
  ipn_manual_entry: boolean
  open_add: boolean
}

type SortKey = 'ref' | 'crit' | 'qtyDesc' | 'qtyAsc' | 'priceDesc'

const SORT_OPTIONS: { value: SortKey; label: string }[] = [
  { value: 'ref', label: 'Reference (A→Z)' },
  { value: 'crit', label: 'Stock criticality' },
  { value: 'qtyDesc', label: 'Stock (high→low)' },
  { value: 'qtyAsc', label: 'Stock (low→high)' },
  { value: 'priceDesc', label: 'Unit price (high→low)' },
]

function partRef(part: Part): string {
  return part.mpn || part.sku || part.name
}

const SORT_FNS: Record<SortKey, (a: Part, b: Part) => number> = {
  ref: (a, b) => partRef(a).localeCompare(partRef(b)),
  crit: (a, b) => a.total_quantity / Math.max(a.min_stock_threshold, 1) - b.total_quantity / Math.max(b.min_stock_threshold, 1),
  qtyDesc: (a, b) => b.total_quantity - a.total_quantity,
  qtyAsc: (a, b) => a.total_quantity - b.total_quantity,
  priceDesc: (a, b) => (b.unit_price ?? 0) - (a.unit_price ?? 0),
}

const STOCK_STATUS_META = {
  out: { label: 'Out of stock', className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
  low: { label: 'Low stock', className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
  ok: { label: 'In stock', className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
}

function stockStatusKey(quantity: number, threshold: number): keyof typeof STOCK_STATUS_META {
  if (quantity === 0) return 'out'
  if (quantity < threshold) return 'low'
  return 'ok'
}

const LIFECYCLE_META: Record<Part['status'], { label: string; className: string }> = {
  active: { label: 'Active', className: 'bg-muted text-muted-foreground' },
  discontinued: { label: 'Discontinued', className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
  obsolete: { label: 'Obsolete', className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
}

function locationLabel(names: string[]): string {
  if (names.length === 0) return '—'
  if (names.length === 1) return names[0]
  return `${names[0]} +${names.length - 1} more`
}

// Text starting with = + - @ (or a tab/CR) is run as a formula by Excel and
// friends, so user-entered fields get a leading quote. Plain numbers (e.g. a
// negative price) are left alone.
function csvEscape(raw: string): string {
  const value = /^[=+\-@\t\r]/.test(raw) && !/^-?\d+(\.\d+)?$/.test(raw) ? `'${raw}` : raw
  if (/[",\n]/.test(value)) {
    return `"${value.replace(/"/g, '""')}"`
  }
  return value
}

function exportCsv(parts: Part[]) {
  const headers = [
    "Name", "MPN", "SKU", "IPN", "Barcode", "Category", "Manufacturer", "Value", "Package",
    "Footprint", "Location", "Supplier", "Unit Price", "Quantity", "Min Stock Threshold",
    "Status", "Tags", "Description",
  ]
  const rows = parts.map((part) => [
    part.name,
    part.mpn || '',
    part.sku || '',
    part.ipn || '',
    part.barcode || '',
    part.category?.name || '',
    part.manufacturer || '',
    part.value || '',
    part.package_type || '',
    part.footprint?.name || '',
    part.location_names.join('; '),
    part.supplier_name || '',
    part.unit_price != null ? part.unit_price.toFixed(2) : '',
    String(part.total_quantity),
    String(part.min_stock_threshold),
    part.status,
    part.tag_names.join('; '),
    part.description || '',
  ])
  const csv = [ headers, ...rows ].map((row) => row.map(csvEscape).join(',')).join('\n')

  const blob = new Blob([ csv ], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `parts-${new Date().toISOString().slice(0, 10)}.csv`
  link.click()
  URL.revokeObjectURL(url)

  toast.success(`${parts.length} part${parts.length !== 1 ? 's' : ''} exported`, {
    description: link.download,
  })
}

function printLabels(parts: Part[]) {
  if (parts.length === 0) return

  const labels = parts.map((part) => html`
    <div style="width:189px;height:95px;border:1px dashed #999;border-radius:4px;padding:8px 10px;box-sizing:border-box;page-break-inside:avoid;">
      <div style="font-family:monospace;font-weight:700;font-size:13px;">${part.mpn || part.sku || part.name}</div>
      <div style="font-size:9.5px;color:#555;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${part.name}</div>
      <div style="font-family:monospace;font-size:10px;margin-top:6px;">${locationLabel(part.location_names)}</div>
    </div>`)

  printDocument(
    'Labels',
    html`<div style="display:flex;flex-wrap:wrap;gap:10px;">${labels}</div>`,
    'font-family:Arial,sans-serif;padding:24px;background:#fff;',
  )
}

function csrfToken(): string {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
}

interface ParsedImportRow {
  name: string
  category: string
  mpn: string
  sku: string
}

function splitCsvLine(line: string, sep: string): string[] {
  const out: string[] = []
  let cur = ''
  let inQuotes = false
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (inQuotes) {
      if (ch === '"') {
        if (line[i + 1] === '"') { cur += '"'; i++ } else { inQuotes = false }
      } else {
        cur += ch
      }
    } else if (ch === '"') {
      inQuotes = true
    } else if (ch === sep) {
      out.push(cur)
      cur = ''
    } else {
      cur += ch
    }
  }
  out.push(cur)
  return out
}

function parseCsvPreview(text: string): { rows: ParsedImportRow[] } | { error: string } {
  const stripped = text.replace(/^\uFEFF/, '')
  const lines = stripped.split(/\r\n|\n|\r/).filter((l) => l.trim().length > 0)
  if (lines.length < 2) return { error: 'File is empty or has no data rows.' }

  const sep = lines[0].includes(';') ? ';' : ','
  const header = splitCsvLine(lines[0], sep).map((h) => h.trim().toLowerCase())
  const col = (names: string[]) => {
    for (const n of names) {
      const i = header.indexOf(n)
      if (i >= 0) return i
    }
    return -1
  }

  const iName = col([ 'name', 'designation', 'désignation' ])
  const iCategory = col([ 'category', 'categorie', 'catégorie' ])
  const iMpn = col([ 'mpn' ])
  const iSku = col([ 'sku', 'reference', 'ref', 'référence' ])

  if (iName < 0 || iCategory < 0) {
    return { error: 'Could not find "Name" and "Category" columns in the header row.' }
  }

  const rows: ParsedImportRow[] = []
  for (let i = 1; i < lines.length; i++) {
    const c = splitCsvLine(lines[i], sep)
    const name = (c[iName] || '').trim()
    const category = (c[iCategory] || '').trim()
    if (!name || !category) continue
    rows.push({
      name,
      category,
      mpn: iMpn >= 0 ? (c[iMpn] || '').trim() : '',
      sku: iSku >= 0 ? (c[iSku] || '').trim() : '',
    })
  }

  if (rows.length === 0) return { error: 'No valid rows found (each row needs a Name and Category).' }
  return { rows }
}

export default function PartsIndex({ parts, initial_query, categories, footprints, suppliers, tags, storage_locations, supplier_lookup_enabled, ipn_manual_entry, open_add }: PartsIndexProps) {
  const { canWrite, canAdminister } = usePermissions()
  const [query, setQuery] = useState(initial_query || '')
  const [categoryId, setCategoryId] = useState<number | 'all'>('all')
  const [fStatus, setFStatus] = useState<string[]>([])
  const [fPackage, setFPackage] = useState<string[]>([])
  const [fFootprint, setFFootprint] = useState<string[]>([])
  const [fSupplier, setFSupplier] = useState<string[]>([])
  const [selected, setSelected] = useState<number[]>([])
  const [page, setPage] = useState(0)
  const [sortKey, setSortKey] = useState<SortKey>('ref')

  const [importOpen, setImportOpen] = useState(false)
  const [importRows, setImportRows] = useState<ParsedImportRow[] | null>(null)
  const [importError, setImportError] = useState('')
  const [importFileName, setImportFileName] = useState('')
  const importFormRef = useRef<HTMLFormElement>(null)

  const [addOpen, setAddOpen] = useState(open_add)
  const openAddDialog = () => setAddOpen(true)

  const [editPartId, setEditPartId] = useState<number | null>(null)
  const [detailPartId, setDetailPartId] = useState<number | null>(null)

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

  const totalUnits = useMemo(() => filtered.reduce((sum, part) => sum + part.total_quantity, 0), [filtered])

  const pageCount = Math.max(1, Math.ceil(sorted.length / PAGE_SIZE))
  const clampedPage = Math.min(page, pageCount - 1)
  const pageSlice = sorted.slice(clampedPage * PAGE_SIZE, clampedPage * PAGE_SIZE + PAGE_SIZE)

  const allIds = sorted.map((p) => p.id)
  const allFilteredSelected = allIds.length > 0 && allIds.every((id) => selected.includes(id))
  const hiddenSelectedCount = selected.filter((id) => !allIds.includes(id)).length

  const pageIds = pageSlice.map((p) => p.id)
  const pageAllSelected = pageIds.length > 0 && pageIds.every((id) => selected.includes(id))
  const pageSomeSelected = pageIds.some((id) => selected.includes(id))

  const toggleRow = (id: number) => {
    setSelected(selected.includes(id) ? selected.filter((x) => x !== id) : [ ...selected, id ])
  }

  // Header checkbox scopes to the current page only — selecting every
  // matching part across pages is an explicit follow-up action (see banner
  // below), not an implicit side effect of "select all".
  const togglePage = () => {
    setSelected(
      pageAllSelected
        ? selected.filter((id) => !pageIds.includes(id))
        : Array.from(new Set([ ...selected, ...pageIds ]))
    )
  }

  const selectAllMatching = () => setSelected(allIds)

  const selectedParts = useMemo(() => parts.filter((p) => selected.includes(p.id)), [parts, selected])

  const [moveOpen, setMoveOpen] = useState(false)
  const [moveLocationId, setMoveLocationId] = useState('')
  const [moveConfirmOpen, setMoveConfirmOpen] = useState(false)
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [bulkSubmitting, setBulkSubmitting] = useState(false)

  const [categoryOpen, setCategoryOpen] = useState(false)
  const [categoryValue, setCategoryValue] = useState('')
  const [categoryConfirmOpen, setCategoryConfirmOpen] = useState(false)
  const [statusOpen, setStatusOpen] = useState(false)
  const [statusValue, setStatusValue] = useState<Part['status'] | ''>('')
  const [statusConfirmOpen, setStatusConfirmOpen] = useState(false)
  const [tagsOpen, setTagsOpen] = useState(false)
  const [tagsMode, setTagsMode] = useState<'add' | 'remove'>('add')
  const [tagsValue, setTagsValue] = useState<number[]>([])
  const [tagsConfirmOpen, setTagsConfirmOpen] = useState(false)
  const [supplierOpen, setSupplierOpen] = useState(false)
  const [supplierValue, setSupplierValue] = useState('')
  const [supplierConfirmOpen, setSupplierConfirmOpen] = useState(false)

  const selectedCount = selected.length
  const plural = selectedCount !== 1 ? 's' : ''

  const openMove = () => {
    setMoveLocationId('')
    setMoveConfirmOpen(false)
    setMoveOpen(true)
  }

  const openCategory = () => {
    setCategoryValue('')
    setCategoryConfirmOpen(false)
    setCategoryOpen(true)
  }

  const openStatus = () => {
    setStatusValue('')
    setStatusConfirmOpen(false)
    setStatusOpen(true)
  }

  const openTags = () => {
    setTagsMode('add')
    setTagsValue([])
    setTagsConfirmOpen(false)
    setTagsOpen(true)
  }

  const openSupplier = () => {
    setSupplierValue('')
    setSupplierConfirmOpen(false)
    setSupplierOpen(true)
  }

  // Shared visit options. On success, the server has applied the action and
  // Inertia has reloaded the (now updated) part list, so the selection is
  // cleared. On error (a rejected bulk action, e.g. a tampered/invalid id —
  // surfaced via the `errors` Inertia prop rather than a plain redirect, see
  // PartsController#bulk_error), only the confirmation step is closed: the
  // selection and the underlying edit dialog stay put so the user can see the
  // flash alert and retry instead of silently losing their in-progress edit.
  const bulkVisitOptions = (closeDialog: () => void, closeConfirm: () => void = closeDialog) => ({
    preserveScroll: true,
    onStart: () => setBulkSubmitting(true),
    onFinish: () => setBulkSubmitting(false),
    onSuccess: () => {
      closeDialog()
      setSelected([])
    },
    onError: () => {
      closeConfirm()
    },
  })

  const submitMove = () => {
    if (!moveLocationId) return
    router.post('/parts/bulk_move',
      { part_ids: selected, storage_location_id: moveLocationId },
      bulkVisitOptions(() => { setMoveConfirmOpen(false); setMoveOpen(false) }, () => setMoveConfirmOpen(false)))
  }

  const submitDelete = () => {
    router.delete('/parts/bulk_destroy', {
      data: { part_ids: selected },
      ...bulkVisitOptions(() => setDeleteOpen(false)),
    })
  }

  const submitCategory = () => {
    if (!categoryValue) return
    router.post('/parts/bulk_update_category',
      { part_ids: selected, category_id: categoryValue },
      bulkVisitOptions(() => { setCategoryConfirmOpen(false); setCategoryOpen(false) }, () => setCategoryConfirmOpen(false)))
  }

  const submitStatus = () => {
    if (!statusValue) return
    router.post('/parts/bulk_update_status',
      { part_ids: selected, status: statusValue },
      bulkVisitOptions(() => { setStatusConfirmOpen(false); setStatusOpen(false) }, () => setStatusConfirmOpen(false)))
  }

  const submitTags = () => {
    if (tagsValue.length === 0) return
    router.post('/parts/bulk_update_tags',
      { part_ids: selected, tag_ids: tagsValue, mode: tagsMode },
      bulkVisitOptions(() => { setTagsConfirmOpen(false); setTagsOpen(false) }, () => setTagsConfirmOpen(false)))
  }

  const submitSupplier = () => {
    if (!supplierValue) return
    router.post('/parts/bulk_assign_supplier',
      { part_ids: selected, supplier_id: supplierValue },
      bulkVisitOptions(() => { setSupplierConfirmOpen(false); setSupplierOpen(false) }, () => setSupplierConfirmOpen(false)))
  }

  const bulkActions = [
    { label: 'Move', icon: Move, action: openMove },
    { label: 'Category', icon: Layers, action: openCategory },
    { label: 'Status', icon: CircleDot, action: openStatus },
    { label: 'Tags', icon: Tags, action: openTags },
    { label: 'Supplier', icon: Truck, action: openSupplier },
    { label: 'Labels', icon: Tag, action: () => printLabels(selectedParts) },
    { label: 'Export', icon: Download, action: () => exportCsv(selectedParts) },
    // Bulk delete is admin-gated server-side (PartsController#bulk_destroy) —
    // hidden here too so members/viewers don't hit a dead-end confirmation
    // dialog for an action the server will always reject.
    ...(canAdminister ? [ { label: 'Delete', icon: Trash2, action: () => setDeleteOpen(true) } ] : []),
  ]

  const handleFilePicked = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    setImportFileName(file.name)
    const reader = new FileReader()
    reader.onload = () => {
      const result = parseCsvPreview(String(reader.result || ''))
      if ('error' in result) {
        setImportError(result.error)
        setImportRows(null)
      } else {
        setImportError('')
        setImportRows(result.rows)
      }
    }
    reader.onerror = () => {
      setImportError('Could not read that file.')
      setImportRows(null)
    }
    reader.readAsText(file)
  }

  const importNewCount = useMemo(() => {
    if (!importRows) return 0
    return importRows.filter((r) => !parts.some((p) => (r.mpn && p.mpn === r.mpn) || (r.sku && p.sku === r.sku))).length
  }, [importRows, parts])
  const importUpdateCount = importRows ? importRows.length - importNewCount : 0

  const closeImport = () => {
    setImportOpen(false)
    setImportRows(null)
    setImportError('')
    setImportFileName('')
  }

  return (
    <AppLayout>
      <Head title="Parts" />

      <div className="-m-4 flex h-[100svh] flex-col">
        {/* Topbar */}
        <div className="flex shrink-0 flex-wrap items-center gap-3 border-b bg-background px-4 py-3 sm:px-5">
          <SidebarTrigger className="-ml-1 md:hidden" />
          <div>
            <h1 className="text-base font-semibold tracking-tight">Inventory</h1>
            <p className="text-xs text-muted-foreground">
              {filtered.length} reference{filtered.length !== 1 ? 's' : ''} · {totalUnits.toLocaleString()} units in stock
            </p>
          </div>
          <div className="flex-1" />
          <div className="relative w-full sm:w-64">
            <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              placeholder="Reference, value, location…"
              className="pl-9"
              value={query}
              onChange={(e) => { setQuery(e.target.value); setPage(0) }}
            />
          </div>
          <ReadOnlyBadge />
          {canWrite && (
            <Button variant="outline" size="sm" onClick={() => setImportOpen(true)}>
              <Upload className="size-4" />
              Import CSV
            </Button>
          )}
          <Button variant="outline" size="sm" onClick={() => exportCsv(sorted)}>
            <Download className="size-4" />
            Export CSV
          </Button>
          {canWrite && (
            <Button size="sm" onClick={openAddDialog}>
              <Plus className="size-4" />
              Add Part
            </Button>
          )}
        </div>

        <div className="px-5 pt-3 empty:pt-0">
          <FlashMessages />
        </div>

        {/* Toolbar */}
        <div className="flex shrink-0 flex-col gap-2 border-b bg-background px-5 py-3">
        {/* Category filter chips + sort */}
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex flex-1 flex-wrap items-center gap-2">
            {categoryChips.length > 0 && (
              <>
                <Button
                  variant={categoryId === 'all' ? 'default' : 'outline'}
                  size="sm"
                  onClick={() => { setCategoryId('all'); setPage(0) }}
                  className={`h-8 gap-1.5 rounded-full border px-3 shadow-none ${categoryId === 'all' ? 'border-primary' : ''}`}
                >
                  All
                  <span className="text-xs opacity-75">{parts.length}</span>
                </Button>
                {categoryChips.map((chip) => (
                  <Button
                    key={chip.id}
                    variant={categoryId === chip.id ? 'default' : 'outline'}
                    size="sm"
                    onClick={() => { setCategoryId(chip.id); setPage(0) }}
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
          {statusOptions.length > 0 && (
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="text-xs font-medium text-muted-foreground">Status</span>
              {statusOptions.map((opt) => (
                <Button
                  key={opt.value}
                  variant={fStatus.includes(opt.value) ? 'default' : 'outline'}
                  size="sm"
                  onClick={() => { toggleFacet(fStatus, setFStatus, opt.value); setPage(0) }}
                  className={`h-7 gap-1 rounded-md border px-2 text-xs shadow-none ${fStatus.includes(opt.value) ? 'border-primary' : ''}`}
                >
                  {opt.label} <span className="opacity-75">({opt.count})</span>
                </Button>
              ))}
            </div>
          )}
          {packageOptions.length > 0 && (
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="text-xs font-medium text-muted-foreground">Package</span>
              {packageOptions.map(([value, count]) => (
                <Button
                  key={value}
                  variant={fPackage.includes(value) ? 'default' : 'outline'}
                  size="sm"
                  onClick={() => { toggleFacet(fPackage, setFPackage, value); setPage(0) }}
                  className={`h-7 gap-1 rounded-md border px-2 text-xs shadow-none ${fPackage.includes(value) ? 'border-primary' : ''}`}
                >
                  {value} <span className="opacity-75">({count})</span>
                </Button>
              ))}
            </div>
          )}
          {footprintOptions.length > 0 && (
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="text-xs font-medium text-muted-foreground">Footprint</span>
              {footprintOptions.map(([value, count]) => (
                <Button
                  key={value}
                  variant={fFootprint.includes(value) ? 'default' : 'outline'}
                  size="sm"
                  onClick={() => { toggleFacet(fFootprint, setFFootprint, value); setPage(0) }}
                  className={`h-7 gap-1 rounded-md border px-2 text-xs shadow-none ${fFootprint.includes(value) ? 'border-primary' : ''}`}
                >
                  {value} <span className="opacity-75">({count})</span>
                </Button>
              ))}
            </div>
          )}
          {supplierOptions.length > 0 && (
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="text-xs font-medium text-muted-foreground">Supplier</span>
              {supplierOptions.map(([value, count]) => (
                <Button
                  key={value}
                  variant={fSupplier.includes(value) ? 'default' : 'outline'}
                  size="sm"
                  onClick={() => { toggleFacet(fSupplier, setFSupplier, value); setPage(0) }}
                  className={`h-7 gap-1 rounded-md border px-2 text-xs shadow-none ${fSupplier.includes(value) ? 'border-primary' : ''}`}
                >
                  {value} <span className="opacity-75">({count})</span>
                </Button>
              ))}
            </div>
          )}
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

        {/* Bulk action bar */}
        {canWrite && selected.length > 0 && (
          <div className="flex shrink-0 items-center gap-3 bg-foreground px-5 py-2.5 text-background">
            <span className="text-sm font-medium">
              {selected.length} selected
              {hiddenSelectedCount > 0 && (
                <span className="ml-1 font-normal text-background/75">
                  (includes {hiddenSelectedCount} hidden by filters)
                </span>
              )}
            </span>
            <div className="h-5 w-px bg-background/25" />
            {bulkActions.map((action) => (
              <Button
                key={action.label}
                variant="ghost"
                size="sm"
                onClick={action.action}
                className="h-7 px-2 font-normal hover:bg-background/10 hover:text-background"
              >
                <action.icon className="size-4" />
                {action.label}
              </Button>
            ))}
            <div className="flex-1" />
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setSelected([])}
              className="h-7 px-2 font-normal text-background/75 hover:bg-background/10 hover:text-background"
            >
              Deselect
            </Button>
          </div>
        )}

        {/* Table */}
        <div className="min-h-0 flex-1 overflow-auto bg-muted/40">
        {parts.length === 0 ? (
          <div className="flex flex-col items-center justify-center p-16">
            <Package className="size-12 text-muted-foreground" />
            <h3 className="mt-4 text-lg font-semibold">No parts yet</h3>
            <p className="mt-2 text-sm text-muted-foreground">
              {canWrite ? 'Get started by adding your first part.' : 'No parts have been added yet.'}
            </p>
            {canWrite && (
              <Button className="mt-4" onClick={openAddDialog}>
                <Plus className="mr-2 size-4" />
                Add Part
              </Button>
            )}
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center p-16 text-center">
            <h3 className="text-lg font-semibold">No results found</h3>
            <p className="mt-2 text-sm text-muted-foreground">
              Try a different search or filter.
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
                      aria-label="Select page"
                    />
                  </TableHead>
                  <TableHead className="py-2">Reference</TableHead>
                  <TableHead className="py-2">IPN</TableHead>
                  <TableHead className="py-2">Category</TableHead>
                  <TableHead className="py-2">Value</TableHead>
                  <TableHead className="py-2">Package</TableHead>
                  <TableHead className="py-2">Location</TableHead>
                  <TableHead className="py-2">Supplier</TableHead>
                  <TableHead className="py-2 text-right">Stock</TableHead>
                  <TableHead className="py-2">Status</TableHead>
                  <TableHead className="py-2 text-right">Stock Value</TableHead>
                  <TableHead className="w-[60px] py-2">Actions</TableHead>
                </TableRow>
                {pageAllSelected && !allFilteredSelected && sorted.length > pageIds.length && (
                  <TableRow className="bg-muted hover:bg-muted">
                    <TableHead colSpan={12} className="py-1.5 text-center text-xs font-normal text-muted-foreground">
                      All {pageIds.length} parts on this page are selected.{' '}
                      <Button
                        type="button"
                        variant="link"
                        onClick={selectAllMatching}
                        className="h-auto p-0 underline underline-offset-2 hover:no-underline"
                      >
                        Select all {sorted.length} parts matching filters
                      </Button>
                    </TableHead>
                  </TableRow>
                )}
              </TableHeader>
              <TableBody>
                {pageSlice.map((part) => {
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
                              onClick={() => setDetailPartId(part.id)}
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
                          <Button variant="ghost" size="icon" onClick={() => setEditPartId(part.id)} aria-label="Edit part">
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
                  {clampedPage * PAGE_SIZE + 1}–{Math.min(clampedPage * PAGE_SIZE + PAGE_SIZE, filtered.length)} of {filtered.length} · Page {clampedPage + 1}/{pageCount}
                </span>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" disabled={clampedPage === 0} onClick={() => setPage(Math.max(0, clampedPage - 1))}>
                    <ChevronLeft className="size-4" />
                    Previous
                  </Button>
                  <Button variant="outline" size="sm" disabled={clampedPage >= pageCount - 1} onClick={() => setPage(Math.min(pageCount - 1, clampedPage + 1))}>
                    Next
                    <ChevronRight className="size-4" />
                  </Button>
                </div>
              </div>
            )}
          </>
        )}
        </div>
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

      {/* CSV Import modal */}
      <Dialog open={importOpen} onOpenChange={(open) => (open ? setImportOpen(true) : closeImport())}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Import inventory</DialogTitle>
            <DialogDescription>
              CSV file — columns are detected automatically (French and English headers both work).
            </DialogDescription>
          </DialogHeader>

          <form ref={importFormRef} action="/parts/import" method="post" encType="multipart/form-data">
            <input type="hidden" name="authenticity_token" value={csrfToken()} />
            <label className="flex cursor-pointer flex-col items-center gap-2 rounded-lg border border-dashed p-8 text-center hover:bg-accent">
              <Upload className="size-6 text-muted-foreground" />
              <span className="text-sm font-medium">Click to choose a file</span>
              <span className="text-xs text-muted-foreground">
                Headers: Name, Category, MPN, SKU, Value, Package, Location, Supplier, Quantity, Min Stock Threshold, Unit Price
              </span>
              <input type="file" name="file" accept=".csv,text/csv" className="hidden" onChange={handleFilePicked} />
            </label>

            {importError && (
              <p className="mt-3 text-sm text-destructive">{importError}</p>
            )}

            {importRows && !importError && (
              <div className="mt-4 space-y-3">
                <div className="text-sm text-muted-foreground">
                  {importFileName} · {importRows.length} row{importRows.length !== 1 ? 's' : ''}
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <div className="rounded-md bg-emerald-100 p-2 text-center dark:bg-emerald-950">
                    <div className="text-lg font-bold text-emerald-700 dark:text-emerald-400">{importNewCount}</div>
                    <div className="text-xs text-emerald-700 dark:text-emerald-400">New</div>
                  </div>
                  <div className="rounded-md bg-blue-100 p-2 text-center dark:bg-blue-950">
                    <div className="text-lg font-bold text-blue-700 dark:text-blue-400">{importUpdateCount}</div>
                    <div className="text-xs text-blue-700 dark:text-blue-400">Updated</div>
                  </div>
                </div>
                <div className="max-h-40 space-y-1 overflow-y-auto rounded-md border p-2">
                  {importRows.slice(0, 8).map((r, i) => {
                    const isNew = !parts.some((p) => (r.mpn && p.mpn === r.mpn) || (r.sku && p.sku === r.sku))
                    return (
                      <div key={i} className="flex items-center gap-2 text-sm">
                        <span className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-semibold ${
                          isNew
                            ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400'
                            : 'bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-400'
                        }`}>
                          {isNew ? 'NEW' : 'UPDATE'}
                        </span>
                        <span className="truncate">{r.name}</span>
                      </div>
                    )
                  })}
                </div>
              </div>
            )}

            <DialogFooter className="mt-4">
              <Button type="button" variant="outline" onClick={closeImport}>
                Cancel
              </Button>
              <Button type="button" disabled={!importRows || !!importError} onClick={() => importFormRef.current?.requestSubmit()}>
                Confirm import
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Bulk move modal */}
      <Dialog open={moveOpen} onOpenChange={setMoveOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Move {selectedCount} part{plural}</DialogTitle>
            <DialogDescription>
              All stock for the selected part{plural} is relocated into the destination location.
              Parts with no stock are skipped.
            </DialogDescription>
          </DialogHeader>

          <div className="min-w-0 space-y-2">
            <Label htmlFor="bulk-move-location">Destination location</Label>
            <Select value={moveLocationId} onValueChange={setMoveLocationId}>
              <SelectTrigger id="bulk-move-location" className="w-full">
                <SelectValue placeholder="Choose a location" />
              </SelectTrigger>
              <SelectContent position="popper">
                {storage_locations.map((loc) => (
                  <SelectItem key={loc.id} value={String(loc.id)} title={loc.name}>{loc.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            {storage_locations.length === 0 && (
              <p className="text-sm text-muted-foreground">No storage locations yet — create one first.</p>
            )}
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setMoveOpen(false)}>Cancel</Button>
            <Button disabled={!moveLocationId || bulkSubmitting} onClick={() => setMoveConfirmOpen(true)}>
              Move part{plural}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <AlertDialog open={moveConfirmOpen} onOpenChange={setMoveConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Move {selectedCount} part{plural}?</AlertDialogTitle>
            <AlertDialogDescription>
              This writes stock-out and stock-in movements for every location currently holding
              the selected part{plural}. This can&apos;t be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={bulkSubmitting}>Cancel</AlertDialogCancel>
            <AlertDialogAction disabled={bulkSubmitting} onClick={(e) => { e.preventDefault(); submitMove() }}>
              {bulkSubmitting ? 'Moving…' : `Move part${plural}`}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Bulk category modal */}
      <Dialog open={categoryOpen} onOpenChange={setCategoryOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Set category for {selectedCount} part{plural}</DialogTitle>
            <DialogDescription>
              Replaces the category on every selected part.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-2">
            <Label htmlFor="bulk-category">Category</Label>
            <Select value={categoryValue} onValueChange={setCategoryValue}>
              <SelectTrigger id="bulk-category">
                <SelectValue placeholder="Choose a category" />
              </SelectTrigger>
              <SelectContent>
                {categories.map((category) => (
                  <SelectItem key={category.id} value={String(category.id)}>{category.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setCategoryOpen(false)}>Cancel</Button>
            <Button disabled={!categoryValue || bulkSubmitting} onClick={() => setCategoryConfirmOpen(true)}>
              Set category
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <AlertDialog open={categoryConfirmOpen} onOpenChange={setCategoryConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Set category for {selectedCount} part{plural}?</AlertDialogTitle>
            <AlertDialogDescription>
              This overwrites the current category on every selected part
              {hiddenSelectedCount > 0 ? ', including parts hidden by your current filters' : ''}.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={bulkSubmitting}>Cancel</AlertDialogCancel>
            <AlertDialogAction disabled={bulkSubmitting} onClick={(e) => { e.preventDefault(); submitCategory() }}>
              {bulkSubmitting ? 'Setting…' : 'Set category'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Bulk status modal */}
      <Dialog open={statusOpen} onOpenChange={setStatusOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Set status for {selectedCount} part{plural}</DialogTitle>
            <DialogDescription>
              Replaces the lifecycle status on every selected part.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-2">
            <Label htmlFor="bulk-status">Status</Label>
            <Select value={statusValue} onValueChange={(value) => setStatusValue(value as Part['status'])}>
              <SelectTrigger id="bulk-status">
                <SelectValue placeholder="Choose a status" />
              </SelectTrigger>
              <SelectContent>
                {(Object.keys(LIFECYCLE_META) as Part['status'][]).map((status) => (
                  <SelectItem key={status} value={status}>{LIFECYCLE_META[status].label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setStatusOpen(false)}>Cancel</Button>
            <Button disabled={!statusValue || bulkSubmitting} onClick={() => setStatusConfirmOpen(true)}>
              Set status
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <AlertDialog open={statusConfirmOpen} onOpenChange={setStatusConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Set status for {selectedCount} part{plural}?</AlertDialogTitle>
            <AlertDialogDescription>
              This overwrites the lifecycle status on every selected part
              {hiddenSelectedCount > 0 ? ', including parts hidden by your current filters' : ''}.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={bulkSubmitting}>Cancel</AlertDialogCancel>
            <AlertDialogAction disabled={bulkSubmitting} onClick={(e) => { e.preventDefault(); submitStatus() }}>
              {bulkSubmitting ? 'Setting…' : 'Set status'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Bulk tags modal */}
      <Dialog open={tagsOpen} onOpenChange={setTagsOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Edit tags for {selectedCount} part{plural}</DialogTitle>
            <DialogDescription>
              Add or remove the chosen tags across every selected part.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            <div className="inline-flex rounded-md border p-0.5">
              {(['add', 'remove'] as const).map((mode) => (
                <Button
                  key={mode}
                  type="button"
                  variant={tagsMode === mode ? 'default' : 'ghost'}
                  size="sm"
                  onClick={() => setTagsMode(mode)}
                  className="h-7 rounded px-3 capitalize"
                >
                  {mode}
                </Button>
              ))}
            </div>

            <div className="space-y-2">
              <Label>Tags</Label>
              <TagPicker tags={tags} value={tagsValue} onChange={setTagsValue} />
            </div>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setTagsOpen(false)}>Cancel</Button>
            <Button disabled={tagsValue.length === 0 || bulkSubmitting} onClick={() => setTagsConfirmOpen(true)}>
              {tagsMode === 'add' ? 'Add tags' : 'Remove tags'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <AlertDialog open={tagsConfirmOpen} onOpenChange={setTagsConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {tagsMode === 'add' ? 'Add' : 'Remove'} tags for {selectedCount} part{plural}?
            </AlertDialogTitle>
            <AlertDialogDescription>
              This {tagsMode === 'add' ? 'adds the chosen tags to' : 'removes the chosen tags from'} every
              selected part{hiddenSelectedCount > 0 ? ', including parts hidden by your current filters' : ''}.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={bulkSubmitting}>Cancel</AlertDialogCancel>
            <AlertDialogAction disabled={bulkSubmitting} onClick={(e) => { e.preventDefault(); submitTags() }}>
              {bulkSubmitting ? 'Saving…' : tagsMode === 'add' ? 'Add tags' : 'Remove tags'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Bulk supplier modal */}
      <Dialog open={supplierOpen} onOpenChange={setSupplierOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Assign supplier for {selectedCount} part{plural}</DialogTitle>
            <DialogDescription>
              Links the supplier to every selected part and marks it preferred.
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-2">
            <Label htmlFor="bulk-supplier">Supplier</Label>
            <Select value={supplierValue} onValueChange={setSupplierValue}>
              <SelectTrigger id="bulk-supplier">
                <SelectValue placeholder="Choose a supplier" />
              </SelectTrigger>
              <SelectContent>
                {suppliers.map((supplier) => (
                  <SelectItem key={supplier.id} value={String(supplier.id)}>{supplier.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            {suppliers.length === 0 && (
              <p className="text-sm text-muted-foreground">No suppliers yet — add one first.</p>
            )}
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setSupplierOpen(false)}>Cancel</Button>
            <Button disabled={!supplierValue || bulkSubmitting} onClick={() => setSupplierConfirmOpen(true)}>
              Assign supplier
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <AlertDialog open={supplierConfirmOpen} onOpenChange={setSupplierConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Assign supplier for {selectedCount} part{plural}?</AlertDialogTitle>
            <AlertDialogDescription>
              This links the chosen supplier to every selected part and marks it preferred, which
              also updates each part&apos;s unit price to match
              {hiddenSelectedCount > 0 ? '. This includes parts hidden by your current filters.' : '.'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={bulkSubmitting}>Cancel</AlertDialogCancel>
            <AlertDialogAction disabled={bulkSubmitting} onClick={(e) => { e.preventDefault(); submitSupplier() }}>
              {bulkSubmitting ? 'Assigning…' : 'Assign supplier'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Bulk delete confirmation */}
      <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete {selectedCount} part{plural}?</AlertDialogTitle>
            <AlertDialogDescription>
              This permanently removes the selected part{plural} along with their stock and
              movement history. This can&apos;t be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={bulkSubmitting}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              disabled={bulkSubmitting}
              onClick={(e) => { e.preventDefault(); submitDelete() }}
              className="bg-destructive text-white hover:bg-destructive/90"
            >
              {bulkSubmitting ? 'Deleting…' : `Delete part${plural}`}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </AppLayout>
  )
}
