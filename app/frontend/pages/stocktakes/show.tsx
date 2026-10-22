import { Head, Link, router } from '@inertiajs/react'
import { FormEvent, KeyboardEvent, useEffect, useMemo, useRef, useState } from 'react'
import { ArrowLeft, Camera, CameraOff, Check, CheckCircle2, Download, Plus, ScanLine, Trash2 } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { useBarcodeScanner } from '@/hooks/use-barcode-scanner'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { StorageLocationSelect, type StorageLocationOption } from '@/components/storage-location-select'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Checkbox } from '@/components/ui/checkbox'
import { Combobox, type ComboboxOption } from '@/components/ui/combobox'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
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
import { cn } from '@/lib/utils'

interface Stocktake {
  id: number
  reference: string | null
  status: 'in_progress' | 'completed'
  blind: boolean
  include_sub_zones: boolean
  notes: string | null
  zone: { id: number; name: string; code: string | null }
  started_by: string | null
  created_at: string
  completed_by: string | null
  completed_at: string | null
  line_count: number
  counted_count: number
  discrepancy_count: number
  units_found: number
  units_missing: number
  value_difference: number
  adjustment_count: number
}

interface StocktakeLine {
  id: number
  part: { id: number; reference: string; ipn: string | null; name: string; unit_price: number | null }
  zone: { id: number; name: string; short_name: string; code: string | null }
  // Null while a blind count hides it.
  expected_quantity: number | null
  counted_quantity: number | null
  difference: number | null
  counted_at: string | null
  counted_by: string | null
  adjustment: { id: number; quantity_delta: number } | null
}

interface PartOption {
  id: number
  reference: string
  name: string
}

interface StocktakeShowProps {
  stocktake: Stocktake
  lines: StocktakeLine[]
  zones: StorageLocationOption[]
  current_zone_id: number | null
  focus_line_id: number | null
  parts: PartOption[]
  currency: string
  errors?: Record<string, string | string[]>
}

type LineFilter = 'all' | 'uncounted' | 'differences'

const ALL_ZONES = ''

function formatDateTime(iso: string) {
  return new Date(iso).toLocaleString(undefined, { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
}

function formatMoney(value: number, currency: string) {
  try {
    return new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(value)
  } catch {
    return `${value.toFixed(2)} ${currency}`
  }
}

function signed(value: number) {
  return value > 0 ? `+${value}` : String(value)
}

function DifferenceBadge({ difference }: { difference: number | null }) {
  if (difference === null) {
    return <span className="text-xs text-muted-foreground">Not counted</span>
  }
  if (difference === 0) {
    return (
      <Badge variant="outline" className="bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400">
        <CheckCircle2 className="size-3.5" /> Match
      </Badge>
    )
  }
  return (
    <Badge
      variant="outline"
      className={difference > 0
        ? 'bg-blue-100 font-mono text-blue-700 dark:bg-blue-950 dark:text-blue-400'
        : 'bg-amber-100 font-mono text-amber-700 dark:bg-amber-950 dark:text-amber-400'}
    >
      {signed(difference)}
    </Badge>
  )
}

export default function StocktakeShow({ stocktake, lines, zones, current_zone_id, focus_line_id, parts, currency, errors }: StocktakeShowProps) {
  const { canWrite } = usePermissions()
  const counting = canWrite && stocktake.status === 'in_progress'
  const [code, setCode] = useState('')
  const [increment, setIncrement] = useState(false)
  const [filter, setFilter] = useState<LineFilter>('all')
  const [search, setSearch] = useState('')
  const [highlightId, setHighlightId] = useState<number | null>(focus_line_id)
  const [addPartId, setAddPartId] = useState('')
  const [completeOpen, setCompleteOpen] = useState(false)
  const [zeroUncounted, setZeroUncounted] = useState(false)
  const [discardOpen, setDiscardOpen] = useState(false)
  const scanInput = useRef<HTMLInputElement>(null)
  const countInputs = useRef(new Map<number, HTMLInputElement>())
  const zoneId = current_zone_id ? String(current_zone_id) : ALL_ZONES
  const base = `/stocktakes/${stocktake.id}`

  // Brings a line into view and, unless each scan adds one, puts the cursor
  // in its count so the quantity can be typed right away.
  const focusLine = (lineId: number | null, typeCount: boolean) => {
    if (lineId === null) return
    setHighlightId(lineId)
    requestAnimationFrame(() => {
      const input = countInputs.current.get(lineId)
      input?.scrollIntoView({ block: 'center', behavior: 'smooth' })
      if (typeCount && input) {
        input.focus()
        input.select()
      } else {
        scanInput.current?.focus()
      }
    })
  }

  useEffect(() => {
    if (focus_line_id) focusLine(focus_line_id, counting)
    else if (counting) scanInput.current?.focus()
    // Only on arrival: later scans focus from their own response.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const submitCode = (value: string) => {
    const trimmed = value.trim()
    if (!trimmed) return
    router.post(`${base}/scan`, { code: trimmed, zone: zoneId, increment }, {
      preserveScroll: true,
      preserveState: true,
      onSuccess: (page) => {
        setFilter('all')
        setSearch('')
        focusLine((page.props as unknown as StocktakeShowProps).focus_line_id, !increment)
      },
    })
  }

  const camera = useBarcodeScanner(submitCode, { continuous: true })

  const submitScan = (e: FormEvent) => {
    e.preventDefault()
    submitCode(code)
    setCode('')
  }

  const changeZone = (value: string) => {
    router.get(base, value ? { zone: value } : {}, { preserveScroll: true, preserveState: true })
  }

  const saveCount = (line: StocktakeLine, raw: string) => {
    const trimmed = raw.trim()
    const quantity = trimmed === '' ? null : Number(trimmed)
    if (quantity === line.counted_quantity) return
    if (quantity !== null && (!Number.isInteger(quantity) || quantity < 0)) return
    router.patch(`${base}/lines/${line.id}`, { stocktake_line: { counted_quantity: trimmed } }, {
      preserveScroll: true,
      preserveState: true,
    })
  }

  const countKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key !== 'Enter') return
    e.preventDefault()
    // Back to the scan field for the next label; leaving the field saves it.
    if (scanInput.current) scanInput.current.focus()
    else e.currentTarget.blur()
  }

  const addPart = () => {
    if (!addPartId) return
    router.post(`${base}/lines`, {
      stocktake_line: { part_id: addPartId, storage_location_id: current_zone_id ?? stocktake.zone.id },
    }, {
      preserveScroll: true,
      preserveState: true,
      onSuccess: (page) => {
        setAddPartId('')
        setFilter('all')
        setSearch('')
        focusLine((page.props as unknown as StocktakeShowProps).focus_line_id, true)
      },
    })
  }

  const partOptions = useMemo<ComboboxOption[]>(
    () => parts.map((part) => ({ value: String(part.id), label: `${part.reference} — ${part.name}` })),
    [parts]
  )

  const visibleLines = useMemo(() => {
    const query = search.trim().toLowerCase()
    return lines.filter((line) => {
      if (current_zone_id && line.zone.id !== current_zone_id) return false
      if (filter === 'uncounted' && line.counted_quantity !== null) return false
      if (filter === 'differences' && !line.difference) return false
      if (query && !`${line.part.reference} ${line.part.ipn ?? ''} ${line.part.name} ${line.zone.name}`.toLowerCase().includes(query)) return false
      return true
    })
  }, [lines, current_zone_id, filter, search])

  const uncountedCount = stocktake.line_count - stocktake.counted_count
  const currentZone = zones.find((zone) => zone.id === current_zone_id)

  return (
    <AppLayout
      header={
        <PageHeader title={`Stocktake ${stocktake.reference ?? ''}`.trim()} subtitle={stocktake.zone.name}>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" asChild>
              <a href={`${base}/export`}>
                <Download className="size-4" />
                Export CSV
              </a>
            </Button>
            {counting && (
              <>
                <Button size="sm" variant="outline" onClick={() => setDiscardOpen(true)}>
                  <Trash2 className="size-4" />
                  Discard
                </Button>
                <Button size="sm" onClick={() => setCompleteOpen(true)}>
                  <Check className="size-4" />
                  Complete stocktake
                </Button>
              </>
            )}
          </div>
        </PageHeader>
      }
    >
      <Head title={`Stocktake ${stocktake.reference ?? ''}`.trim()} />

      <div className="space-y-6">
        <FlashMessages errors={errors} />

        <Link href="/stocktakes" className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground">
          <ArrowLeft className="size-4" />
          All stocktakes
        </Link>

        {counting && (
          <div className="grid items-start gap-4 lg:grid-cols-[minmax(0,320px)_1fr]">
            {/* Camera */}
            <div className="rounded-2xl border border-zinc-800 bg-zinc-950 p-3 shadow-sm">
              <div className="relative aspect-[4/3] overflow-hidden rounded-xl bg-zinc-900">
                <video
                  ref={camera.videoRef}
                  className={`absolute inset-0 size-full object-cover transition-opacity ${camera.active ? 'opacity-100' : 'opacity-0'}`}
                  muted
                  playsInline
                />
                {!camera.active ? (
                  <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 px-4 text-center">
                    <Button type="button" onClick={camera.start} disabled={camera.starting}>
                      <Camera className="size-4" />
                      {camera.starting ? 'Starting camera…' : 'Start camera'}
                    </Button>
                    <span className="text-xs text-zinc-400">Scan zone and part labels one after the other</span>
                  </div>
                ) : (
                  <Button
                    type="button"
                    variant="ghost"
                    onClick={camera.stop}
                    className="absolute top-2 right-2 h-auto gap-1.5 rounded-lg border border-white/20 bg-black/40 px-2.5 py-1.5 text-xs text-white backdrop-blur hover:bg-black/60 hover:text-white has-[>svg]:px-2.5 dark:hover:bg-black/60"
                  >
                    <CameraOff className="size-3.5" />
                    Stop
                  </Button>
                )}
              </div>
              {camera.error && (
                <div className="mt-3 rounded-lg border border-red-900/50 bg-red-950/40 px-3 py-2 text-xs text-red-300">
                  {camera.error}
                </div>
              )}
            </div>

            {/* Scan, zone, add */}
            <Card>
              <CardContent className="space-y-4">
                <form onSubmit={submitScan} className="flex gap-2">
                  <Input
                    ref={scanInput}
                    value={code}
                    onChange={(e) => setCode(e.target.value)}
                    placeholder="Scan or type a part or zone code…"
                    aria-label="Scan a code"
                    className="h-10"
                  />
                  <Button type="submit" variant="outline" className="h-10">
                    <ScanLine className="size-4" />
                    Scan
                  </Button>
                </form>

                <div className="flex items-center justify-between gap-4">
                  <div>
                    <Label htmlFor="stocktake-increment">Each scan adds 1</Label>
                    <p className="text-xs text-muted-foreground">
                      {increment ? 'Scan every item once.' : 'Scan a label, then type the quantity counted and press Enter.'}
                    </p>
                  </div>
                  <Switch id="stocktake-increment" checked={increment} onCheckedChange={setIncrement} />
                </div>

                <div className="grid gap-4 sm:grid-cols-2">
                  <div className="space-y-2">
                    <Label htmlFor="stocktake-current-zone">Counting in</Label>
                    <StorageLocationSelect
                      id="stocktake-current-zone"
                      locations={zones}
                      value={zoneId}
                      onValueChange={changeZone}
                      noneLabel="All zones of this count"
                      placeholder="All zones of this count"
                    />
                    <p className="text-xs text-muted-foreground">Scanning a zone label picks it too.</p>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="stocktake-add-part">Found something else?</Label>
                    <div className="flex gap-2">
                      <Combobox
                        id="stocktake-add-part"
                        options={partOptions}
                        value={addPartId}
                        onValueChange={setAddPartId}
                        placeholder="Add a part…"
                        searchPlaceholder="Search parts…"
                        className="min-w-0 flex-1"
                      />
                      <Button type="button" variant="outline" disabled={!addPartId} onClick={addPart} aria-label="Add part to the count">
                        <Plus className="size-4" />
                      </Button>
                    </div>
                    <p className="text-xs text-muted-foreground">
                      Added to {currentZone ? currentZone.name : stocktake.zone.name}.
                    </p>
                  </div>
                </div>
              </CardContent>
            </Card>
          </div>
        )}

        {/* Summary */}
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <SummaryCard label="Counted" value={`${stocktake.counted_count} / ${stocktake.line_count}`} />
          <SummaryCard label="Differences" value={stocktake.discrepancy_count} tone={stocktake.discrepancy_count > 0 ? 'amber' : undefined} />
          <SummaryCard
            label="Units found / missing"
            value={`+${stocktake.units_found} / −${stocktake.units_missing}`}
          />
          <SummaryCard
            label="Value difference"
            value={formatMoney(stocktake.value_difference, currency)}
            tone={stocktake.value_difference < 0 ? 'amber' : undefined}
          />
        </div>

        <Card className={`border-l-[3px] ${stocktake.status === 'completed' ? 'border-l-emerald-500' : 'border-l-blue-500'}`}>
          <CardContent className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
            {stocktake.status === 'completed' ? (
              <span className="font-medium">
                Completed {stocktake.completed_at && formatDateTime(stocktake.completed_at)}
                {stocktake.completed_by && ` by ${stocktake.completed_by}`}
                {' · '}
                {stocktake.adjustment_count === 0
                  ? 'stock matched the count'
                  : `${stocktake.adjustment_count} adjustment${stocktake.adjustment_count !== 1 ? 's' : ''} recorded`}
              </span>
            ) : (
              <span className="font-medium">In progress: nothing changes in stock until the stocktake is completed.</span>
            )}
            <span className="text-muted-foreground">
              Started {formatDateTime(stocktake.created_at)}{stocktake.started_by && ` by ${stocktake.started_by}`}
            </span>
            {stocktake.include_sub_zones && <Badge variant="outline">With sub-zones</Badge>}
            {stocktake.blind && <Badge variant="outline">Blind count</Badge>}
            {stocktake.notes && <p className="w-full text-muted-foreground">{stocktake.notes}</p>}
          </CardContent>
        </Card>

        {/* Lines */}
        <Card className="gap-0 overflow-hidden py-0">
          <div className="flex flex-wrap items-center gap-2 border-b px-4 py-3">
            {([
              ['all', 'All'],
              ['uncounted', `${stocktake.status === 'completed' ? 'Not counted' : 'To count'} (${uncountedCount})`],
              ['differences', `Differences (${stocktake.discrepancy_count})`],
            ] as Array<[LineFilter, string]>).map(([value, label]) => (
              <Button key={value} size="sm" variant={filter === value ? 'secondary' : 'ghost'} onClick={() => setFilter(value)}>
                {label}
              </Button>
            ))}
            <div className="flex-1" />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Filter parts…"
              aria-label="Filter parts"
              className="h-8 w-full sm:w-56"
            />
          </div>
          {visibleLines.length === 0 ? (
            <div className="px-4 py-8 text-center text-sm text-muted-foreground">
              {lines.length === 0
                ? 'The ledger has no stock in this zone. Scan or add the parts you find.'
                : 'No line matches.'}
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Part</TableHead>
                  <TableHead className="hidden sm:table-cell">Zone</TableHead>
                  <TableHead className="text-right">Expected</TableHead>
                  <TableHead className="text-right">Counted</TableHead>
                  <TableHead className="hidden sm:table-cell">Difference</TableHead>
                  {stocktake.status === 'completed' && <TableHead className="text-right">Adjustment</TableHead>}
                </TableRow>
              </TableHeader>
              <TableBody>
                {visibleLines.map((line) => (
                  <TableRow
                    key={line.id}
                    data-line-id={line.id}
                    className={cn(highlightId === line.id && 'bg-primary/5')}
                  >
                    <TableCell>
                      <div className="font-mono text-sm font-semibold">{line.part.reference}</div>
                      <div className="max-w-[140px] truncate text-xs text-muted-foreground sm:max-w-[260px]">
                        {line.part.ipn && line.part.ipn !== line.part.reference && <span className="mr-1.5 font-mono">{line.part.ipn}</span>}
                        {line.part.name !== line.part.reference && line.part.name}
                      </div>
                      <div className="max-w-[140px] truncate text-xs text-muted-foreground sm:hidden">
                        {line.zone.short_name}{line.zone.code && ` · ${line.zone.code}`}
                      </div>
                    </TableCell>
                    <TableCell className="hidden sm:table-cell">
                      <div className="max-w-[220px] truncate text-sm" title={line.zone.name}>{line.zone.short_name}</div>
                      {line.zone.code && <div className="font-mono text-xs text-muted-foreground">{line.zone.code}</div>}
                    </TableCell>
                    <TableCell className="text-right font-mono">
                      {line.expected_quantity === null ? <span className="text-muted-foreground">hidden</span> : line.expected_quantity}
                    </TableCell>
                    <TableCell className="text-right">
                      {counting ? (
                        <div className="flex items-center justify-end gap-1.5">
                          {line.counted_quantity === null && line.expected_quantity !== null && (
                            <Button
                              type="button"
                              size="sm"
                              variant="ghost"
                              className="h-8 px-2 text-xs"
                              title="Counted what was expected"
                              onClick={() => saveCount(line, String(line.expected_quantity))}
                            >
                              <Check className="size-3.5" />
                              {line.expected_quantity}
                            </Button>
                          )}
                          <Input
                            // Remount when the saved count changes so the field shows it.
                            key={`${line.id}-${line.counted_quantity ?? ''}`}
                            ref={(el) => {
                              if (el) countInputs.current.set(line.id, el)
                              else countInputs.current.delete(line.id)
                            }}
                            type="number"
                            min={0}
                            inputMode="numeric"
                            defaultValue={line.counted_quantity ?? ''}
                            aria-label={`Counted ${line.part.reference}`}
                            className="h-8 w-20 text-right font-mono sm:w-24"
                            onBlur={(e) => saveCount(line, e.target.value)}
                            onKeyDown={countKeyDown}
                          />
                        </div>
                      ) : (
                        <span className="font-mono">{line.counted_quantity ?? '—'}</span>
                      )}
                      {line.counted_by && (
                        <div className="mt-0.5 hidden text-[11px] text-muted-foreground sm:block">{line.counted_by}</div>
                      )}
                      {line.counted_quantity !== null && (
                        <div className="mt-1 sm:hidden">
                          <DifferenceBadge difference={line.difference} />
                        </div>
                      )}
                    </TableCell>
                    <TableCell className="hidden sm:table-cell">
                      <DifferenceBadge difference={line.difference} />
                    </TableCell>
                    {stocktake.status === 'completed' && (
                      <TableCell className="text-right font-mono text-sm">
                        {line.adjustment ? signed(line.adjustment.quantity_delta) : '—'}
                      </TableCell>
                    )}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </Card>
      </div>

      {/* Complete */}
      <AlertDialog open={completeOpen} onOpenChange={setCompleteOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Complete this stocktake?</AlertDialogTitle>
            <AlertDialogDescription>
              {stocktake.discrepancy_count === 0
                ? 'No counted line differs from the stock.'
                : `${stocktake.discrepancy_count} counted line${stocktake.discrepancy_count !== 1 ? 's differ' : ' differs'} from the stock: each gets an adjustment movement so the stock matches the count.`}
              {' '}The stocktake is then closed and kept as a report.
            </AlertDialogDescription>
          </AlertDialogHeader>
          {uncountedCount > 0 && (
            <div className="flex items-start gap-2 rounded-lg border p-3 text-sm">
              <Checkbox
                id="stocktake-zero-uncounted"
                checked={zeroUncounted}
                onCheckedChange={(checked) => setZeroUncounted(checked === true)}
                className="mt-0.5"
              />
              <Label htmlFor="stocktake-zero-uncounted" className="block font-normal leading-snug">
                Set the {uncountedCount} uncounted line{uncountedCount !== 1 ? 's' : ''} to zero
                <span className="block text-xs text-muted-foreground">
                  Otherwise they keep their stock, as if they hadn't been part of the count.
                </span>
              </Label>
            </div>
          )}
          <AlertDialogFooter>
            <AlertDialogCancel>Keep counting</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                router.post(`${base}/complete`, { zero_uncounted: zeroUncounted }, { preserveScroll: true })
                setCompleteOpen(false)
              }}
            >
              Complete and adjust stock
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Discard */}
      <AlertDialog open={discardOpen} onOpenChange={setDiscardOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Discard this stocktake?</AlertDialogTitle>
            <AlertDialogDescription>
              The counts entered so far are deleted. Stock isn't affected.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                router.delete(base)
                setDiscardOpen(false)
              }}
            >
              Discard
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </AppLayout>
  )
}

function SummaryCard({ label, value, tone }: { label: string; value: string | number; tone?: 'amber' }) {
  return (
    <Card>
      <CardContent>
        <div className="text-sm text-muted-foreground">{label}</div>
        <div className={cn('mt-1 font-mono text-2xl font-bold', tone === 'amber' && 'text-amber-600 dark:text-amber-400')}>{value}</div>
      </CardContent>
    </Card>
  )
}
