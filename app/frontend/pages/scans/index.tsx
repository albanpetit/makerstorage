import { Head, Link, router } from '@inertiajs/react'
import { FormEvent, useEffect, useMemo, useState } from 'react'
import { AlertTriangle, Box, Camera, CameraOff, Check, ChevronRight, ClipboardCheck, Cpu, ExternalLink, MapPin, PackageCheck, Plus, ScanLine } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { useBarcodeScanner } from '@/hooks/use-barcode-scanner'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { PartDetailSheet } from '@/components/part-detail-sheet'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { StorageLocationSelect } from '@/components/storage-location-select'

interface ScanLocationOption {
  id: number
  name: string
  code: string | null
  location_type: string
  quantity: number
}

interface ScannedPart {
  id: number
  reference: string
  name: string
  category: { name: string; color: string | null } | null
  total_quantity: number
  stock_status: 'out_of_stock' | 'low_stock' | 'sufficient'
  locations: ScanLocationOption[]
}

interface ScannedZone {
  id: number
  name: string
  full_path: string
  location_type: string
  parts_count: number
  total_quantity: number
  children_count: number
  // Stocked parts held directly in the zone, largest quantity first (capped).
  contents: Array<{ id: number; reference: string; name: string; quantity: number }>
  // The stocktake already counting this zone, if any.
  stocktake: { id: number; reference: string | null } | null
}

// The fields read from a distributor's bag label (ECIA DataMatrix or LCSC QR).
interface SupplierLabel {
  provider: string | null
  provider_name: string
  mpn: string | null
  supplier_sku: string | null
  customer_part_number: string | null
  manufacturer: string | null
  quantity: number | null
  order_number: string | null
  lot: string | null
  date_code: string | null
  country_of_origin: string | null
}

interface SupplierLabelResult {
  kind: 'supplier_label'
  label: SupplierLabel
  // Stamped on the receipt movement (e.g. "DigiKey 84512345").
  reference: string
  // The inventory part the label matched, if any.
  part: ScannedPart | null
  // The same bag was already received (same part, order and quantity).
  previous_receipt: { created_at: string; quantity: number; location_name: string } | null
  open_orders: Array<{ id: number; reference: string | null; quantity: number }>
}

type ScanResult =
  | { kind: 'part'; part: ScannedPart }
  | { kind: 'location'; location: ScannedZone }
  | SupplierLabelResult
  | { kind: 'unknown' }

interface RecentScan {
  id: number
  created_at: string
  quantity_delta: number
  reference: string
  location_name: string
  category_color: string | null
}

interface ScanPageProps {
  code: string | null
  result: ScanResult | null
  recent_scans: RecentScan[]
  today_count: number
  allow_negative_stock: boolean
  preferred_location_id: number | null
  errors?: Record<string, string | string[]>
}

const STOCK_STATUS_CLASS: Record<ScannedPart['stock_status'], string> = {
  out_of_stock: 'text-red-600 dark:text-red-400',
  low_stock: 'text-amber-600 dark:text-amber-400',
  sufficient: 'text-emerald-600 dark:text-emerald-400',
}

const QR_GHOST_CELLS: Array<[number, number]> = [
  [0, 0], [1, 0], [2, 0], [4, 0], [5, 0],
  [0, 1], [2, 1], [5, 1],
  [0, 2], [1, 2], [2, 2], [3, 2], [5, 2],
  [1, 3], [3, 3], [4, 3],
  [0, 4], [2, 4], [3, 4], [5, 4],
  [1, 5], [2, 5], [4, 5], [5, 5],
]

function formatAgo(iso: string) {
  const seconds = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000)
  if (seconds < 60) return 'just now'
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes} min ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours} h ago`
  return `${Math.floor(hours / 24)} d ago`
}

function MatchBadge({ tone, label }: { tone: 'success' | 'error'; label: string }) {
  const className = tone === 'success'
    ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400'
    : 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400'
  return (
    <span className={`rounded-full px-2.5 py-0.5 text-[11px] font-semibold tracking-wide uppercase ${className}`}>
      {label}
    </span>
  )
}

function ResultCardHeader({ tone, label, code }: { tone: 'success' | 'error'; label: string; code: string }) {
  return (
    <div className="flex items-center gap-2.5 border-b px-4 py-3">
      <MatchBadge tone={tone} label={label} />
      <span className="font-mono text-xs text-muted-foreground">{code}</span>
    </div>
  )
}

export default function ScansIndex({ code, result, recent_scans, today_count, allow_negative_stock, preferred_location_id, errors }: ScanPageProps) {
  const { canWrite } = usePermissions()
  const [codeInput, setCodeInput] = useState('')
  const [delta, setDelta] = useState(0)
  const [locationId, setLocationId] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [detailPartId, setDetailPartId] = useState<number | null>(null)
  const [receiveQuantity, setReceiveQuantity] = useState('')

  const camera = useBarcodeScanner((code) => {
    router.get('/scan', { code }, { preserveState: true, preserveScroll: true })
  })

  const part = result?.kind === 'part' ? result.part : null
  const labelResult = result?.kind === 'supplier_label' ? result : null
  // The part whose zones the zone picker offers: a counted part, or the part a
  // supplier label matched.
  const targetPart = part ?? labelResult?.part ?? null

  useEffect(() => {
    setDelta(0)
    setLocationId('')
    setReceiveQuantity(labelResult?.label.quantity ? String(labelResult.label.quantity) : '')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [code])

  const selectedLocation = useMemo(() => {
    if (!targetPart) return null
    return targetPart.locations.find((location) => String(location.id) === locationId)
      ?? targetPart.locations.find((location) => location.id === preferred_location_id)
      ?? targetPart.locations[0]
      ?? null
  }, [targetPart, locationId, preferred_location_id])

  const projected = (selectedLocation?.quantity ?? 0) + delta

  const submitScan = (e: FormEvent) => {
    e.preventDefault()
    const trimmed = codeInput.trim()
    if (!trimmed) return
    setCodeInput('')
    router.get('/scan', { code: trimmed }, { preserveState: true, preserveScroll: true })
  }

  const validateMovement = () => {
    if (!part || !selectedLocation || delta === 0) return
    router.post('/scan/movements', {
      scan: { part_id: part.id, storage_location_id: selectedLocation.id, quantity_delta: delta },
    }, {
      preserveScroll: true,
      preserveState: true,
      onStart: () => setSubmitting(true),
      onFinish: () => setSubmitting(false),
      onSuccess: () => setDelta(0),
    })
  }

  const receiveCount = Number.parseInt(receiveQuantity, 10)
  const canReceive = Number.isInteger(receiveCount) && receiveCount > 0 && !!selectedLocation

  const receiveBag = () => {
    if (!labelResult?.part || !selectedLocation || !canReceive) return
    router.post('/scan/receipts', {
      receipt: {
        part_id: labelResult.part.id,
        storage_location_id: selectedLocation.id,
        quantity: receiveCount,
        reference: labelResult.reference,
      },
    }, {
      preserveScroll: true,
      onStart: () => setSubmitting(true),
      onFinish: () => setSubmitting(false),
    })
  }

  // Opens the add-part dialog prefilled from the label; it comes back here
  // once the part (and its opening stock) is created.
  const createPartFromLabel = (label: SupplierLabel) => {
    const prefill = Object.fromEntries(
      Object.entries({
        mpn: label.mpn,
        manufacturer: label.manufacturer,
        provider: label.provider,
        supplier_sku: label.supplier_sku,
        quantity: label.quantity?.toString(),
      }).filter(([, value]) => value),
    )
    router.get('/parts', { new: 1, prefill })
  }

  const matchLabel = !result ? '—'
    : result.kind === 'part' ? 'Part'
    : result.kind === 'location' ? 'Zone'
    : result.kind === 'supplier_label' ? 'Supplier label'
    : 'Unknown'

  return (
    <AppLayout
      header={
        <PageHeader title="Scanner" subtitle="Scan a QR code to locate a zone, count a component or receive a supplier bag">
          <span className="inline-flex items-center gap-2 text-xs text-muted-foreground">
            <span className="size-1.5 animate-pulse rounded-full bg-emerald-500" />
            Scanner ready
          </span>
        </PageHeader>
      }
    >
      <Head title="Scanner" />

      <div className="mx-auto max-w-5xl space-y-4">
        <FlashMessages errors={errors} />

        <div className="grid items-start gap-4 lg:grid-cols-2">
          {/* Viewfinder */}
          <div className="rounded-2xl border border-zinc-800 bg-zinc-950 p-4 shadow-sm">
            <div className="relative aspect-square overflow-hidden rounded-xl bg-[radial-gradient(circle_at_50%_40%,#1c1c22_0%,#0c0c0e_75%)]">
              {/* Live camera feed — always mounted so the decoder can attach to it */}
              <video
                ref={camera.videoRef}
                className={`absolute inset-0 size-full object-cover transition-opacity ${camera.active ? 'opacity-100' : 'opacity-0'}`}
                muted
                playsInline
              />

              {/* Framing overlay — only meaningful while the camera is live */}
              {camera.active && (
                <div className="absolute inset-[14%]">
                  <div className="absolute top-0 left-0 size-8 rounded-tl-lg border-t-[3px] border-l-[3px] border-primary" />
                  <div className="absolute top-0 right-0 size-8 rounded-tr-lg border-t-[3px] border-r-[3px] border-primary" />
                  <div className="absolute bottom-0 left-0 size-8 rounded-bl-lg border-b-[3px] border-l-[3px] border-primary" />
                  <div className="absolute right-0 bottom-0 size-8 rounded-br-lg border-r-[3px] border-b-[3px] border-primary" />
                  <div className="absolute inset-x-[6%] h-0.5 animate-[scan-line_2.6s_ease-in-out_infinite] bg-gradient-to-r from-transparent via-primary to-transparent shadow-[0_0_12px_2px_var(--primary)]" />
                </div>
              )}

              {/* Idle state — ghost QR + start button */}
              {!camera.active && (
                <>
                  <svg
                    viewBox="0 0 6 6"
                    className="absolute top-1/2 left-1/2 size-28 -translate-x-1/2 -translate-y-1/2 opacity-[0.18]"
                    fill="#ffffff"
                    aria-hidden
                  >
                    {QR_GHOST_CELLS.map(([x, y], i) => (
                      <rect key={i} x={x} y={y} width={1} height={1} />
                    ))}
                  </svg>
                  <div className="absolute inset-x-0 bottom-4 flex flex-col items-center gap-2 px-4">
                    <Button type="button" onClick={camera.start} disabled={camera.starting} className="h-10">
                      <Camera className="size-4" />
                      {camera.starting ? 'Starting camera…' : 'Start camera'}
                    </Button>
                    <span className="text-xs text-zinc-400">…or use a hardware scanner / type a code below</span>
                  </div>
                </>
              )}

              {/* Stop control while live */}
              {camera.active && (
                <Button
                  type="button"
                  variant="ghost"
                  onClick={camera.stop}
                  className="absolute top-2.5 right-2.5 h-auto gap-1.5 rounded-lg border border-white/20 bg-black/40 px-2.5 py-1.5 text-xs text-white backdrop-blur hover:bg-black/60 hover:text-white has-[>svg]:px-2.5 dark:hover:bg-black/60"
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

            <form onSubmit={submitScan} className="mt-3.5 space-y-2">
              <Input
                value={codeInput}
                onChange={(e) => setCodeInput(e.target.value)}
                placeholder="IPN, barcode, SKU, MPN, or zone code…"
                className="h-11 border-zinc-800 bg-zinc-900 text-zinc-50 placeholder:text-zinc-500"
              />
              <Button type="submit" variant="outline" className="h-11 w-full border-zinc-700 bg-zinc-900 text-zinc-50 hover:bg-zinc-800 hover:text-zinc-50">
                <ScanLine className="size-4" />
                Look up code
              </Button>
            </form>

            <div className="mt-2.5 flex gap-2">
              <div className="flex-1 rounded-lg border border-zinc-800 bg-zinc-900 p-2 text-center">
                <div className="text-[11px] text-zinc-400">Counts today</div>
                <div className="font-mono text-base font-bold text-zinc-50">{today_count}</div>
              </div>
              <div className="flex-1 rounded-lg border border-zinc-800 bg-zinc-900 p-2 text-center">
                <div className="text-[11px] text-zinc-400">Match</div>
                <div className="mt-0.5 text-sm font-semibold text-zinc-50">{matchLabel}</div>
              </div>
            </div>
          </div>

          {/* Result + recent scans */}
          <div className="space-y-4">
            {part && code && (
              <Card className="gap-0 overflow-hidden py-0">
                <ResultCardHeader tone="success" label="✓ Scan matched" code={code} />
                <CardContent className="p-4">
                  <div className="flex items-start gap-3">
                    <div
                      className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-muted"
                      style={part.category?.color ? { backgroundColor: `${part.category.color}22`, color: part.category.color } : undefined}
                    >
                      <Cpu className="size-5" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="font-mono text-base font-bold">{part.reference}</div>
                      <div className="truncate text-sm text-muted-foreground">{part.name}</div>
                      {selectedLocation && (
                        <div className="mt-1.5 flex items-center gap-1.5 text-xs text-muted-foreground">
                          <MapPin className="size-3.5 shrink-0" />
                          <span className="truncate">{selectedLocation.name}</span>
                        </div>
                      )}
                    </div>
                    <div className="shrink-0 text-right">
                      <div className="text-[11px] text-muted-foreground">In stock</div>
                      <div className={`font-mono text-2xl font-bold ${STOCK_STATUS_CLASS[part.stock_status]}`}>
                        {(selectedLocation?.quantity ?? 0).toLocaleString()}
                      </div>
                      {part.locations.length > 1 && (
                        <div className="text-[11px] text-muted-foreground">of {part.total_quantity.toLocaleString()} total</div>
                      )}
                    </div>
                  </div>

                  {part.locations.length > 1 && (
                    <div className="mt-3">
                      <StorageLocationSelect
                        locations={part.locations.map((location) => (location.quantity > 0 ? { ...location, hint: location.quantity.toLocaleString() } : location))}
                        value={String(selectedLocation?.id ?? '')}
                        onValueChange={setLocationId}
                        placeholder="Select a location"
                      />
                    </div>
                  )}

                  {!canWrite ? null : part.locations.length === 0 ? (
                    <div className="mt-4 rounded-xl bg-muted p-4 text-center text-sm text-muted-foreground">
                      No storage zone exists yet.{' '}
                      <Link href="/storage_locations" className="font-medium text-foreground underline underline-offset-2">
                        Create one
                      </Link>{' '}
                      to record movements.
                    </div>
                  ) : (
                    <div className="mt-4 rounded-xl bg-muted p-4">
                      <div className="mb-2.5 text-center text-xs font-medium text-muted-foreground">Quick count</div>
                      <div className="flex items-center justify-center gap-4">
                        <Button
                          type="button"
                          variant="outline"
                          className="size-11 rounded-xl text-xl font-semibold text-red-600 dark:text-red-400"
                          aria-label="Remove one"
                          disabled={!allow_negative_stock && projected <= 0}
                          onClick={() => setDelta((d) => d - 1)}
                        >
                          −
                        </Button>
                        <div className="min-w-24 text-center">
                          <div
                            className={`font-mono text-3xl leading-none font-bold ${
                              delta > 0 ? 'text-emerald-600 dark:text-emerald-400' : delta < 0 ? 'text-red-600 dark:text-red-400' : ''
                            }`}
                          >
                            {delta > 0 ? `+${delta}` : delta}
                          </div>
                          <div className="mt-1 text-[11px] text-muted-foreground">→ {projected.toLocaleString()} after</div>
                        </div>
                        <Button
                          type="button"
                          variant="outline"
                          className="size-11 rounded-xl text-xl font-semibold text-emerald-600 dark:text-emerald-400"
                          aria-label="Add one"
                          onClick={() => setDelta((d) => d + 1)}
                        >
                          +
                        </Button>
                      </div>
                    </div>
                  )}

                  <div className="mt-4 flex gap-2">
                    <Button variant="outline" className="flex-1" onClick={() => setDetailPartId(part.id)}>
                      <ExternalLink className="size-4" />
                      Open part
                    </Button>
                    {canWrite && (
                      <Button
                        className="flex-1"
                        disabled={delta === 0 || !selectedLocation || submitting}
                        onClick={validateMovement}
                      >
                        <Check className="size-4" />
                        Validate movement
                      </Button>
                    )}
                  </div>
                </CardContent>
              </Card>
            )}

            {result?.kind === 'location' && code && (
              <Card className="gap-0 overflow-hidden py-0">
                <ResultCardHeader tone="success" label="✓ Scan matched" code={code} />
                <CardContent className="p-4">
                  <div className="flex items-start gap-3">
                    <div className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-muted">
                      <Box className="size-5" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="text-base font-bold">{result.location.name}</div>
                      <div className="truncate text-sm text-muted-foreground">{result.location.full_path}</div>
                      <div className="mt-1.5 flex items-center gap-2">
                        <Badge variant="outline" className="capitalize">{result.location.location_type}</Badge>
                        {result.location.children_count > 0 && (
                          <span className="text-xs text-muted-foreground">
                            {result.location.children_count} sub-zone{result.location.children_count !== 1 ? 's' : ''}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                  <div className="mt-4 grid grid-cols-2 gap-2">
                    <div className="rounded-xl bg-muted p-3 text-center">
                      <div className="text-xs text-muted-foreground">Parts stored</div>
                      <div className="font-mono text-xl font-bold">{result.location.parts_count.toLocaleString()}</div>
                    </div>
                    <div className="rounded-xl bg-muted p-3 text-center">
                      <div className="text-xs text-muted-foreground">Units in stock</div>
                      <div className="font-mono text-xl font-bold">{result.location.total_quantity.toLocaleString()}</div>
                    </div>
                  </div>
                  {result.location.contents.length > 0 && (
                    <div className="mt-4 overflow-hidden rounded-xl border">
                      <div className="border-b bg-muted/50 px-3 py-2 text-xs font-medium text-muted-foreground">
                        Contents{result.location.parts_count > result.location.contents.length
                          ? ` · top ${result.location.contents.length} of ${result.location.parts_count}`
                          : ''}
                      </div>
                      <div className="max-h-80 divide-y overflow-y-auto">
                        {result.location.contents.map((item) => (
                          <Button
                            key={item.id}
                            type="button"
                            variant="ghost"
                            className="flex h-auto w-full items-center justify-start gap-3 rounded-none px-3 py-2 text-left font-normal"
                            onClick={() => router.get('/scan', { code: `part:${item.id}`, zone: result.location.id }, { preserveScroll: true })}
                          >
                            <span className="min-w-0 flex-1">
                              <span className="block truncate font-mono text-sm font-semibold">{item.reference}</span>
                              <span className="block truncate text-xs text-muted-foreground">{item.name}</span>
                            </span>
                            <span className="shrink-0 font-mono text-sm font-semibold">{item.quantity.toLocaleString()}</span>
                            <ChevronRight className="size-4 shrink-0 text-muted-foreground" />
                          </Button>
                        ))}
                      </div>
                    </div>
                  )}
                  <Button variant="outline" className="mt-4 w-full" asChild>
                    <Link href={`/storage_locations?zone=${result.location.id}`}>
                      <Box className="size-4" />
                      Open zone
                    </Link>
                  </Button>
                  {canWrite && (result.location.stocktake ? (
                    <Button variant="outline" className="mt-2 w-full" asChild>
                      <Link href={`/stocktakes/${result.location.stocktake.id}?zone=${result.location.id}`}>
                        <ClipboardCheck className="size-4" />
                        Continue stocktake {result.location.stocktake.reference}
                      </Link>
                    </Button>
                  ) : (
                    <Button
                      variant="outline"
                      className="mt-2 w-full"
                      onClick={() => router.post('/stocktakes', { stocktake: { storage_location_id: result.location.id } })}
                    >
                      <ClipboardCheck className="size-4" />
                      Count this zone
                    </Button>
                  ))}
                </CardContent>
              </Card>
            )}

            {labelResult && (
              <Card className="gap-0 overflow-hidden py-0">
                <ResultCardHeader
                  tone={labelResult.part ? 'success' : 'error'}
                  label={labelResult.part ? '✓ Bag matched' : 'New part'}
                  code={`${labelResult.label.provider_name} label`}
                />
                <CardContent className="p-4">
                  <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
                    {([
                      ['MPN', labelResult.label.mpn],
                      ['Manufacturer', labelResult.label.manufacturer],
                      [`${labelResult.label.provider_name} part number`, labelResult.label.supplier_sku],
                      ['Customer part number', labelResult.label.customer_part_number],
                      ['Quantity', labelResult.label.quantity?.toLocaleString()],
                      ['Order', labelResult.label.order_number],
                      ['Lot', labelResult.label.lot],
                      ['Date code', labelResult.label.date_code],
                    ] as Array<[string, string | null | undefined]>).filter(([, value]) => value).map(([term, value]) => (
                      <div key={term} className="min-w-0">
                        <dt className="text-[11px] text-muted-foreground">{term}</dt>
                        <dd className="truncate font-mono text-sm font-semibold">{value}</dd>
                      </div>
                    ))}
                  </dl>

                  {labelResult.part ? (
                    <>
                      <div className="mt-4 flex items-start gap-3 rounded-xl border p-3">
                        <div
                          className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-muted"
                          style={labelResult.part.category?.color ? { backgroundColor: `${labelResult.part.category.color}22`, color: labelResult.part.category.color } : undefined}
                        >
                          <Cpu className="size-5" />
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="font-mono text-sm font-bold">{labelResult.part.reference}</div>
                          <div className="truncate text-xs text-muted-foreground">{labelResult.part.name}</div>
                        </div>
                        <div className="shrink-0 text-right">
                          <div className="text-[11px] text-muted-foreground">In stock</div>
                          <div className={`font-mono text-lg font-bold ${STOCK_STATUS_CLASS[labelResult.part.stock_status]}`}>
                            {labelResult.part.total_quantity.toLocaleString()}
                          </div>
                        </div>
                      </div>

                      {labelResult.previous_receipt && (
                        <Alert className="mt-3">
                          <AlertTriangle className="size-4" />
                          <AlertDescription>
                            This bag was already received {formatAgo(labelResult.previous_receipt.created_at)} (+{labelResult.previous_receipt.quantity.toLocaleString()} into {labelResult.previous_receipt.location_name}). Receiving it again counts it twice.
                          </AlertDescription>
                        </Alert>
                      )}

                      {labelResult.open_orders.length > 0 && (
                        <Alert className="mt-3">
                          <AlertTriangle className="size-4" />
                          <AlertDescription>
                            <span>
                              On open order{labelResult.open_orders.length > 1 ? 's' : ''}{' '}
                              {labelResult.open_orders.map((order, index) => (
                                <span key={order.id}>
                                  {index > 0 && ', '}
                                  <Link href={`/orders/${order.id}`} className="font-medium text-foreground underline underline-offset-2">
                                    {order.reference || `#${order.id}`}
                                  </Link>{' '}
                                  ({order.quantity.toLocaleString()})
                                </span>
                              ))}
                              . Receiving the bag here doesn't close the order: receive the order instead, or cancel its line, so the stock isn't counted twice.
                            </span>
                          </AlertDescription>
                        </Alert>
                      )}

                      {canWrite && (labelResult.part.locations.length === 0 ? (
                        <div className="mt-4 rounded-xl bg-muted p-4 text-center text-sm text-muted-foreground">
                          No storage zone exists yet.{' '}
                          <Link href="/storage_locations" className="font-medium text-foreground underline underline-offset-2">
                            Create one
                          </Link>{' '}
                          to receive the bag.
                        </div>
                      ) : (
                        <div className="mt-4 space-y-2">
                          <StorageLocationSelect
                            locations={labelResult.part.locations.map((location) => (location.quantity > 0 ? { ...location, hint: location.quantity.toLocaleString() } : location))}
                            value={String(selectedLocation?.id ?? '')}
                            onValueChange={setLocationId}
                            placeholder="Select a location"
                          />
                          <div className="flex gap-2">
                            <Input
                              type="number"
                              min={1}
                              inputMode="numeric"
                              aria-label="Quantity received"
                              value={receiveQuantity}
                              onChange={(e) => setReceiveQuantity(e.target.value)}
                              className="w-28 font-mono"
                            />
                            <Button className="flex-1" disabled={!canReceive || submitting} onClick={receiveBag}>
                              <PackageCheck className="size-4" />
                              Receive {canReceive ? receiveCount.toLocaleString() : ''}
                            </Button>
                          </div>
                        </div>
                      ))}

                      <Button variant="outline" className="mt-2 w-full" onClick={() => setDetailPartId(labelResult.part!.id)}>
                        <ExternalLink className="size-4" />
                        Open part
                      </Button>
                    </>
                  ) : (
                    <>
                      <p className="mt-4 text-sm text-muted-foreground">
                        No part in the inventory matches this label's part numbers.
                        {canWrite && ' Create it from the label: its quantity becomes the opening stock.'}
                      </p>
                      {canWrite && (
                        <Button className="mt-3 w-full" onClick={() => createPartFromLabel(labelResult.label)}>
                          <Plus className="size-4" />
                          Create part
                        </Button>
                      )}
                    </>
                  )}
                </CardContent>
              </Card>
            )}

            {result?.kind === 'unknown' && code && (
              <Card className="gap-0 overflow-hidden py-0">
                <ResultCardHeader tone="error" label="✗ Unknown code" code={code} />
                <CardContent className="px-4 py-5 text-sm text-muted-foreground">
                  No part or storage zone matches this code. Codes are matched against part IPNs, barcodes, SKUs, MPNs, zone codes, and DigiKey, Mouser or LCSC bag labels.
                </CardContent>
              </Card>
            )}

            {!result && (
              <Card className="border-dashed py-10 shadow-none">
                <CardContent className="flex flex-col items-center text-center">
                  <div className="flex size-11 items-center justify-center rounded-xl bg-muted">
                    <ScanLine className="size-5 text-muted-foreground" />
                  </div>
                  <div className="mt-3 text-sm font-semibold">Waiting for a scan</div>
                  <p className="mt-1 text-sm text-muted-foreground">
                    The scanned component, zone or supplier bag will appear here with its quick actions.
                  </p>
                </CardContent>
              </Card>
            )}

            {/* Recent scans */}
            <Card className="gap-0 overflow-hidden py-0">
              <div className="border-b px-4 py-3 text-sm font-semibold">Recent scans</div>
              {recent_scans.length === 0 ? (
                <div className="px-4 py-6 text-sm text-muted-foreground">
                  Counts recorded from the scanner will appear here.
                </div>
              ) : (
                <div className="divide-y">
                  {recent_scans.map((scan) => (
                    <div key={scan.id} className="flex items-center gap-3 px-4 py-2.5">
                      <span
                        className="size-2 shrink-0 rounded-sm"
                        style={{ backgroundColor: scan.category_color || 'var(--muted-foreground)' }}
                      />
                      <div className="min-w-0 flex-1">
                        <div className="truncate font-mono text-sm font-semibold">{scan.reference}</div>
                        <div className="truncate text-xs text-muted-foreground">{scan.location_name}</div>
                      </div>
                      <span className="shrink-0 font-mono text-xs text-muted-foreground">{formatAgo(scan.created_at)}</span>
                      <span
                        className={`shrink-0 font-mono text-xs font-semibold ${
                          scan.quantity_delta > 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400'
                        }`}
                      >
                        {scan.quantity_delta > 0 ? `+${scan.quantity_delta}` : scan.quantity_delta}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </Card>
          </div>
        </div>
      </div>

      {/* Part detail sidebar */}
      <PartDetailSheet
        partId={detailPartId}
        open={detailPartId !== null}
        onOpenChange={(open) => !open && setDetailPartId(null)}
      />
    </AppLayout>
  )
}
