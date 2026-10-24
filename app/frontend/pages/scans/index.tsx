import { Head, Link, router, usePage } from '@inertiajs/react'
import { FormEvent, useEffect, useMemo, useState } from 'react'
import { AlertTriangle, Box, Camera, CameraOff, Check, ChevronRight, ClipboardCheck, Clock, Cpu, ExternalLink, MapPin, PackageCheck, Plus, RefreshCw, ScanLine, Trash2, WifiOff } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { useBarcodeScanner } from '@/hooks/use-barcode-scanner'
import { useOfflineScanner } from '@/hooks/use-offline-scanner'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { PartDetailSheet } from '@/components/part-detail-sheet'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { StorageLocationSelect } from '@/components/storage-location-select'
import { typeMeta } from '@/components/storage-locations/zone-meta'
import { t, tn, tx, intlLocale } from '@/lib/i18n'
import { formatQuantity, parseQuantity, sumQuantities } from '@/lib/quantity'
import { normalizeCode, type ScanResult, type ScannedPart, type SupplierLabel } from '@/lib/offline-scanner'

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

interface SharedAuth {
  [key: string]: unknown
  auth?: {
    user?: { email: string }
    current_organization?: { id: number } | null
  }
}

// A scan answered on the device while the server can't be reached.
interface LocalScan {
  code: string
  // Set when a part is opened from a scanned zone's contents.
  zoneId: number | null
  // Distinguishes two scans of the same code (each starts a fresh count).
  nonce: number
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
  if (seconds < 60) return t('just now')
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return t('{minutes} min ago', { minutes })
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return t('{hours} h ago', { hours })
  return t('{days} d ago', { days: Math.floor(hours / 24) })
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

export default function ScansIndex({ code: serverCode, result: serverResult, recent_scans, today_count, allow_negative_stock, preferred_location_id: serverPreferredLocationId, errors }: ScanPageProps) {
  const { canWrite } = usePermissions()
  const { auth } = usePage<SharedAuth>().props
  const offline = useOfflineScanner({
    organizationId: auth?.current_organization?.id ?? null,
    userKey: auth?.user?.email.toLowerCase() ?? null,
    canWrite,
  })
  const [codeInput, setCodeInput] = useState('')
  const [delta, setDelta] = useState(0)
  const [locationId, setLocationId] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [detailPartId, setDetailPartId] = useState<number | null>(null)
  const [receiveQuantity, setReceiveQuantity] = useState('')
  const [localScan, setLocalScan] = useState<LocalScan | null>(null)
  const [savedOffline, setSavedOffline] = useState<string | null>(null)

  // A scan answered on the device replaces the server's answer until the next
  // scan that reaches the server. Its result is worked out again as scans are
  // queued, so the stock shown includes them.
  const code = localScan ? localScan.code : serverCode
  const result: ScanResult | null = localScan
    ? (offline.lookup?.lookup(localScan.code) ?? { kind: 'unknown' })
    : serverResult
  const preferred_location_id = localScan ? localScan.zoneId : serverPreferredLocationId
  const scanKey = localScan ? `${localScan.code}#${localScan.nonce}` : serverCode
  const allowNegativeStock = localScan ? (offline.snapshot?.allow_negative_stock ?? allow_negative_stock) : allow_negative_stock
  // Actions that need the server (part sheet, zone page, stocktakes, orders,
  // creating a part) are hidden while scans are answered on the device.
  const onDevice = offline.active || localScan !== null

  const scanLocally = (raw: string, zoneId: number | null = null) => {
    setLocalScan((previous) => ({ code: normalizeCode(raw), zoneId, nonce: (previous?.nonce ?? 0) + 1 }))
  }

  const lookupCode = (raw: string, zoneId: number | null = null) => {
    setSavedOffline(null)
    if (offline.active) {
      scanLocally(raw, zoneId)
      return
    }
    router.get('/scan', zoneId ? { code: raw, zone: zoneId } : { code: raw }, {
      preserveState: true,
      preserveScroll: true,
      onSuccess: () => setLocalScan(null),
      onNetworkError: () => {
        offline.markUnreachable()
        if (offline.lookup) scanLocally(raw, zoneId)
        return false
      },
    })
  }

  const camera = useBarcodeScanner((code) => lookupCode(code))

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
  }, [scanKey])

  const selectedLocation = useMemo(() => {
    if (!targetPart) return null
    return targetPart.locations.find((location) => String(location.id) === locationId)
      ?? targetPart.locations.find((location) => location.id === preferred_location_id)
      ?? targetPart.locations[0]
      ?? null
  }, [targetPart, locationId, preferred_location_id])

  const projected = sumQuantities([ selectedLocation?.quantity ?? 0, delta ])

  // Back online, once the queued scans are sent: ask the server again for
  // what's on screen, so its stock and actions come back. Not while a count
  // is being typed.
  const waiting = offline.pending.filter((scan) => !scan.error).length
  useEffect(() => {
    if (localScan && offline.online && !offline.syncing && waiting === 0 && delta === 0) {
      lookupCode(localScan.code, localScan.zoneId)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [offline.online, offline.syncing, waiting])

  const submitScan = (e: FormEvent) => {
    e.preventDefault()
    const trimmed = codeInput.trim()
    if (!trimmed) return
    setCodeInput('')
    lookupCode(trimmed)
  }

  const unreachable = () => {
    offline.markUnreachable()
    setSavedOffline(t('The server could not be reached, so nothing was saved. The scanner now works offline: validate again to keep it on this device.'))
  }

  const validateMovement = async () => {
    if (!part || !selectedLocation || delta === 0) return
    if (onDevice) {
      await offline.enqueue({
        kind: 'count',
        part_id: part.id,
        storage_location_id: selectedLocation.id,
        quantity: delta,
        reference: null,
        part_reference: part.reference,
        location_name: selectedLocation.name,
      })
      setDelta(0)
      setSavedOffline(t('Saved on this device. It will be sent when the server can be reached.'))
      if (offline.online) void offline.sync()
      return
    }
    router.post('/scan/movements', {
      scan: { part_id: part.id, storage_location_id: selectedLocation.id, quantity_delta: delta },
    }, {
      preserveScroll: true,
      preserveState: true,
      onStart: () => setSubmitting(true),
      onFinish: () => setSubmitting(false),
      onSuccess: () => setDelta(0),
      onNetworkError: () => {
        unreachable()
        return false
      },
    })
  }

  const receiveCount = parseQuantity(receiveQuantity) ?? 0
  const canReceive = receiveCount > 0 && !!selectedLocation

  const receiveBag = async () => {
    if (!labelResult?.part || !selectedLocation || !canReceive) return
    if (onDevice) {
      await offline.enqueue({
        kind: 'receipt',
        part_id: labelResult.part.id,
        storage_location_id: selectedLocation.id,
        quantity: receiveCount,
        reference: labelResult.reference,
        part_reference: labelResult.part.reference,
        location_name: selectedLocation.name,
      })
      setLocalScan(null)
      setSavedOffline(t('Bag saved on this device: +{quantity} × {reference} into {zone}. It will be sent when the server can be reached.', {
        quantity: receiveCount.toLocaleString(intlLocale()),
        reference: labelResult.part.reference,
        zone: selectedLocation.name,
      }))
      if (offline.online) void offline.sync()
      return
    }
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
      onNetworkError: () => {
        unreachable()
        return false
      },
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
    : result.kind === 'part' ? t('Part')
    : result.kind === 'location' ? t('Zone')
    : result.kind === 'supplier_label' ? t('Supplier label')
    : t('Unknown')

  return (
    <AppLayout
      header={
        <PageHeader title={t('Scanner')} subtitle={t('Scan a QR code to locate a zone, count a component or receive a supplier bag')}>
          {offline.online ? (
            <span className="inline-flex items-center gap-2 text-xs text-muted-foreground">
              <span className="size-1.5 animate-pulse rounded-full bg-emerald-500" />
              {t('Scanner ready')}
            </span>
          ) : (
            <span className="inline-flex items-center gap-2 text-xs font-medium text-amber-600 dark:text-amber-400">
              <WifiOff className="size-3.5" />
              {t('Offline')}
            </span>
          )}
        </PageHeader>
      }
    >
      <Head title={t('Scanner')} />

      <div className="mx-auto max-w-5xl space-y-4">
        <FlashMessages errors={errors} />

        {savedOffline && (
          <Alert>
            <Clock className="size-4" />
            <AlertDescription>{savedOffline}</AlertDescription>
          </Alert>
        )}

        <div className="grid grid-cols-1 items-start gap-4 lg:grid-cols-2">
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
                      {camera.starting ? t('Starting camera…') : t('Start camera')}
                    </Button>
                    <span className="text-xs text-zinc-400">{t('…or use a hardware scanner / type a code below')}</span>
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
                  {t('Stop')}
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
                placeholder={t('IPN, barcode, SKU, MPN, or zone code…')}
                className="h-11 border-zinc-800 bg-zinc-900 text-zinc-50 placeholder:text-zinc-500"
              />
              <Button type="submit" variant="outline" className="h-11 w-full border-zinc-700 bg-zinc-900 text-zinc-50 hover:bg-zinc-800 hover:text-zinc-50">
                <ScanLine className="size-4" />
                {t('Look up code')}
              </Button>
            </form>

            <div className="mt-2.5 flex gap-2">
              <div className="flex-1 rounded-lg border border-zinc-800 bg-zinc-900 p-2 text-center">
                <div className="text-[11px] text-zinc-400">{t('Counts today')}</div>
                <div className="font-mono text-base font-bold text-zinc-50">{today_count}</div>
              </div>
              <div className="flex-1 rounded-lg border border-zinc-800 bg-zinc-900 p-2 text-center">
                <div className="text-[11px] text-zinc-400">{t('Match')}</div>
                <div className="mt-0.5 text-sm font-semibold text-zinc-50">{matchLabel}</div>
              </div>
            </div>

            <div className="mt-2.5 flex items-center gap-2 rounded-lg border border-zinc-800 bg-zinc-900 px-3 py-2 text-xs text-zinc-400">
              {offline.online ? <Check className="size-3.5 shrink-0" /> : <WifiOff className="size-3.5 shrink-0" />}
              <div className="min-w-0 flex-1">
                {offline.storageError ? t('This browser can\'t keep data on the device, so the scanner needs the server.')
                  : offline.snapshot ? (offline.active
                    ? t('Offline: scans are answered from the data on this device, updated {ago}.', { ago: formatAgo(offline.snapshot.generated_at) })
                    : t('Ready to scan offline · data updated {ago}.', { ago: formatAgo(offline.snapshot.generated_at) }))
                  : offline.online ? t('Preparing offline scanning…')
                  : t('No offline data on this device yet: open the scanner once while the server can be reached.')}
                {offline.snapshot && !window.isSecureContext && (
                  <div className="mt-0.5">{t('Keep this page open: reopening it offline needs HTTPS.')}</div>
                )}
              </div>
              {offline.online && !offline.storageError && (
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  className="size-7 shrink-0 text-zinc-400 hover:bg-zinc-800 hover:text-zinc-50"
                  aria-label={t('Refresh offline data')}
                  onClick={() => void offline.refreshSnapshot()}
                >
                  <RefreshCw className="size-3.5" />
                </Button>
              )}
            </div>
          </div>

          {/* Result + recent scans */}
          <div className="space-y-4">
            {part && code && (
              <Card className="gap-0 overflow-hidden py-0">
                <ResultCardHeader tone="success" label={t('✓ Scan matched')} code={code} />
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
                      <div className="text-[11px] text-muted-foreground">{t('In stock')}</div>
                      <div className={`font-mono text-2xl font-bold ${STOCK_STATUS_CLASS[part.stock_status]}`}>
                        {formatQuantity(selectedLocation?.quantity ?? 0)}
                      </div>
                      {part.locations.length > 1 && (
                        <div className="text-[11px] text-muted-foreground">{t('of {total} total', { total: formatQuantity(part.total_quantity) })}</div>
                      )}
                    </div>
                  </div>

                  {part.locations.length > 1 && (
                    <div className="mt-3">
                      <StorageLocationSelect
                        locations={part.locations.map((location) => (location.quantity > 0 ? { ...location, hint: location.quantity.toLocaleString(intlLocale()) } : location))}
                        value={String(selectedLocation?.id ?? '')}
                        onValueChange={setLocationId}
                        placeholder={t('Select a location')}
                      />
                    </div>
                  )}

                  {!canWrite ? null : part.locations.length === 0 ? (
                    <div className="mt-4 rounded-xl bg-muted p-4 text-center text-sm text-muted-foreground">
                      {tx('No storage zone exists yet. {link} to record movements.', {
                        link: (
                          <Link href="/storage_locations" className="font-medium text-foreground underline underline-offset-2">
                            {t('Create one')}
                          </Link>
                        ),
                      })}
                    </div>
                  ) : (
                    <div className="mt-4 rounded-xl bg-muted p-4">
                      <div className="mb-2.5 text-center text-xs font-medium text-muted-foreground">{t('Quick count')}</div>
                      <div className="flex items-center justify-center gap-4">
                        <Button
                          type="button"
                          variant="outline"
                          className="size-11 rounded-xl text-xl font-semibold text-red-600 dark:text-red-400"
                          aria-label={t('Remove one')}
                          disabled={!allowNegativeStock && projected <= 0}
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
                          <div className="mt-1 text-[11px] text-muted-foreground">{t('→ {quantity} after', { quantity: formatQuantity(projected) })}</div>
                        </div>
                        <Button
                          type="button"
                          variant="outline"
                          className="size-11 rounded-xl text-xl font-semibold text-emerald-600 dark:text-emerald-400"
                          aria-label={t('Add one')}
                          onClick={() => setDelta((d) => d + 1)}
                        >
                          +
                        </Button>
                      </div>
                    </div>
                  )}

                  <div className="mt-4 flex gap-2">
                    {!onDevice && (
                      <Button variant="outline" className="flex-1" onClick={() => setDetailPartId(part.id)}>
                        <ExternalLink className="size-4" />
                        {t('Open part')}
                      </Button>
                    )}
                    {canWrite && (
                      <Button
                        className="flex-1"
                        disabled={delta === 0 || !selectedLocation || submitting}
                        onClick={validateMovement}
                      >
                        <Check className="size-4" />
                        {onDevice ? t('Save on this device') : t('Validate movement')}
                      </Button>
                    )}
                  </div>
                </CardContent>
              </Card>
            )}

            {result?.kind === 'location' && code && (
              <Card className="gap-0 overflow-hidden py-0">
                <ResultCardHeader tone="success" label={t('✓ Scan matched')} code={code} />
                <CardContent className="p-4">
                  <div className="flex items-start gap-3">
                    <div className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-muted">
                      <Box className="size-5" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="text-base font-bold">{result.location.name}</div>
                      <div className="truncate text-sm text-muted-foreground">{result.location.full_path}</div>
                      <div className="mt-1.5 flex items-center gap-2">
                        <Badge variant="outline">{typeMeta(result.location.location_type).label}</Badge>
                        {result.location.children_count > 0 && (
                          <span className="text-xs text-muted-foreground">
                            {tn('{count} sub-zone', '{count} sub-zones', result.location.children_count)}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                  <div className="mt-4 grid grid-cols-2 gap-2">
                    <div className="rounded-xl bg-muted p-3 text-center">
                      <div className="text-xs text-muted-foreground">{t('Parts stored')}</div>
                      <div className="font-mono text-xl font-bold">{result.location.parts_count.toLocaleString(intlLocale())}</div>
                    </div>
                    <div className="rounded-xl bg-muted p-3 text-center">
                      <div className="text-xs text-muted-foreground">{t('Units in stock')}</div>
                      <div className="font-mono text-xl font-bold">{result.location.total_quantity.toLocaleString(intlLocale())}</div>
                    </div>
                  </div>
                  {result.location.contents.length > 0 && (
                    <div className="mt-4 overflow-hidden rounded-xl border">
                      <div className="border-b bg-muted/50 px-3 py-2 text-xs font-medium text-muted-foreground">
                        {t('Contents')}{result.location.parts_count > result.location.contents.length
                          ? t(' · top {shown} of {count}', { shown: result.location.contents.length, count: result.location.parts_count })
                          : ''}
                      </div>
                      <div className="max-h-80 divide-y overflow-y-auto">
                        {result.location.contents.map((item) => (
                          <Button
                            key={item.id}
                            type="button"
                            variant="ghost"
                            className="flex h-auto w-full items-center justify-start gap-3 rounded-none px-3 py-2 text-left font-normal"
                            onClick={() => lookupCode(`part:${item.id}`, result.location.id)}
                          >
                            <span className="min-w-0 flex-1">
                              <span className="block truncate font-mono text-sm font-semibold">{item.reference}</span>
                              <span className="block truncate text-xs text-muted-foreground">{item.name}</span>
                            </span>
                            <span className="shrink-0 font-mono text-sm font-semibold">{item.quantity.toLocaleString(intlLocale())}</span>
                            <ChevronRight className="size-4 shrink-0 text-muted-foreground" />
                          </Button>
                        ))}
                      </div>
                    </div>
                  )}
                  {!onDevice && (
                    <Button variant="outline" className="mt-4 w-full" asChild>
                      <Link href={`/storage_locations?zone=${result.location.id}`}>
                        <Box className="size-4" />
                        {t('Open zone')}
                      </Link>
                    </Button>
                  )}
                  {canWrite && !onDevice && (result.location.stocktake ? (
                    <Button variant="outline" className="mt-2 w-full" asChild>
                      <Link href={`/stocktakes/${result.location.stocktake.id}?zone=${result.location.id}`}>
                        <ClipboardCheck className="size-4" />
                        {t('Continue stocktake {reference}', { reference: result.location.stocktake.reference ?? '' })}
                      </Link>
                    </Button>
                  ) : (
                    <Button
                      variant="outline"
                      className="mt-2 w-full"
                      onClick={() => router.post('/stocktakes', { stocktake: { storage_location_id: result.location.id } })}
                    >
                      <ClipboardCheck className="size-4" />
                      {t('Count this zone')}
                    </Button>
                  ))}
                </CardContent>
              </Card>
            )}

            {labelResult && (
              <Card className="gap-0 overflow-hidden py-0">
                <ResultCardHeader
                  tone={labelResult.part ? 'success' : 'error'}
                  label={labelResult.part ? t('✓ Bag matched') : t('New part')}
                  code={t('{provider} label', { provider: labelResult.label.provider_name })}
                />
                <CardContent className="p-4">
                  <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
                    {([
                      ['MPN', labelResult.label.mpn],
                      [t('Manufacturer'), labelResult.label.manufacturer],
                      [t('{provider} part number', { provider: labelResult.label.provider_name }), labelResult.label.supplier_sku],
                      [t('Customer part number'), labelResult.label.customer_part_number],
                      [t('Quantity'), labelResult.label.quantity?.toLocaleString(intlLocale())],
                      [t('Order'), labelResult.label.order_number],
                      [t('Lot'), labelResult.label.lot],
                      [t('Date code'), labelResult.label.date_code],
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
                          <div className="text-[11px] text-muted-foreground">{t('In stock')}</div>
                          <div className={`font-mono text-lg font-bold ${STOCK_STATUS_CLASS[labelResult.part.stock_status]}`}>
                            {labelResult.part.total_quantity.toLocaleString(intlLocale())}
                          </div>
                        </div>
                      </div>

                      {labelResult.previous_receipt && (
                        <Alert className="mt-3">
                          <AlertTriangle className="size-4" />
                          <AlertDescription>
                            {t('This bag was already received {ago} (+{quantity} into {location}). Receiving it again counts it twice.', {
                              ago: formatAgo(labelResult.previous_receipt.created_at),
                              quantity: labelResult.previous_receipt.quantity.toLocaleString(intlLocale()),
                              location: labelResult.previous_receipt.location_name,
                            })}
                          </AlertDescription>
                        </Alert>
                      )}

                      {labelResult.open_orders.length > 0 && (
                        <Alert className="mt-3">
                          <AlertTriangle className="size-4" />
                          <AlertDescription>
                            <span>
                              {tn('On open order', 'On open orders', labelResult.open_orders.length)}{' '}
                              {labelResult.open_orders.map((order, index) => (
                                <span key={order.id}>
                                  {index > 0 && ', '}
                                  {onDevice ? (
                                    <span className="font-medium text-foreground">{order.reference || `#${order.id}`}</span>
                                  ) : (
                                    <Link href={`/orders/${order.id}`} className="font-medium text-foreground underline underline-offset-2">
                                      {order.reference || `#${order.id}`}
                                    </Link>
                                  )}{' '}
                                  ({order.quantity.toLocaleString(intlLocale())})
                                </span>
                              ))}
                              . {t('Receiving the bag here doesn\'t close the order: receive the order instead, or cancel its line, so the stock isn\'t counted twice.')}
                            </span>
                          </AlertDescription>
                        </Alert>
                      )}

                      {canWrite && (labelResult.part.locations.length === 0 ? (
                        <div className="mt-4 rounded-xl bg-muted p-4 text-center text-sm text-muted-foreground">
                          {tx('No storage zone exists yet. {link} to receive the bag.', {
                            link: (
                              <Link href="/storage_locations" className="font-medium text-foreground underline underline-offset-2">
                                {t('Create one')}
                              </Link>
                            ),
                          })}
                        </div>
                      ) : (
                        <div className="mt-4 space-y-2">
                          <StorageLocationSelect
                            locations={labelResult.part.locations.map((location) => (location.quantity > 0 ? { ...location, hint: location.quantity.toLocaleString(intlLocale()) } : location))}
                            value={String(selectedLocation?.id ?? '')}
                            onValueChange={setLocationId}
                            placeholder={t('Select a location')}
                          />
                          <div className="flex gap-2">
                            <Input
                              type="number"
                              min={0}
                              step="any"
                              inputMode="decimal"
                              aria-label={t('Quantity received')}
                              value={receiveQuantity}
                              onChange={(e) => setReceiveQuantity(e.target.value)}
                              className="w-28 font-mono"
                            />
                            <Button className="flex-1" disabled={!canReceive || submitting} onClick={receiveBag}>
                              <PackageCheck className="size-4" />
                              {!canReceive ? t('Receive')
                                : onDevice ? t('Receive {quantity} on this device', { quantity: receiveCount.toLocaleString(intlLocale()) })
                                : t('Receive {quantity}', { quantity: receiveCount.toLocaleString(intlLocale()) })}
                            </Button>
                          </div>
                        </div>
                      ))}

                      {!onDevice && (
                        <Button variant="outline" className="mt-2 w-full" onClick={() => setDetailPartId(labelResult.part!.id)}>
                          <ExternalLink className="size-4" />
                          {t('Open part')}
                        </Button>
                      )}
                    </>
                  ) : (
                    <>
                      <p className="mt-4 text-sm text-muted-foreground">
                        {t('No part in the inventory matches this label\'s part numbers.')}
                        {canWrite && !onDevice && ` ${t('Create it from the label: its quantity becomes the opening stock.')}`}
                        {canWrite && onDevice && ` ${t('Creating it needs the server: scan the bag again once it can be reached.')}`}
                      </p>
                      {canWrite && !onDevice && (
                        <Button className="mt-3 w-full" onClick={() => createPartFromLabel(labelResult.label)}>
                          <Plus className="size-4" />
                          {t('Create part')}
                        </Button>
                      )}
                    </>
                  )}
                </CardContent>
              </Card>
            )}

            {result?.kind === 'unknown' && code && (
              <Card className="gap-0 overflow-hidden py-0">
                <ResultCardHeader tone="error" label={t('✗ Unknown code')} code={code} />
                <CardContent className="px-4 py-5 text-sm text-muted-foreground">
                  {t('No part or storage zone matches this code. Codes are matched against part IPNs, barcodes, SKUs, MPNs, zone codes, and DigiKey, Mouser or LCSC bag labels.')}
                </CardContent>
              </Card>
            )}

            {!result && (
              <Card className="border-dashed py-10 shadow-none">
                <CardContent className="flex flex-col items-center text-center">
                  <div className="flex size-11 items-center justify-center rounded-xl bg-muted">
                    <ScanLine className="size-5 text-muted-foreground" />
                  </div>
                  <div className="mt-3 text-sm font-semibold">{t('Waiting for a scan')}</div>
                  <p className="mt-1 text-sm text-muted-foreground">
                    {t('The scanned component, zone or supplier bag will appear here with its quick actions.')}
                  </p>
                </CardContent>
              </Card>
            )}

            {/* Scans recorded offline, waiting to be sent */}
            {offline.pending.length > 0 && (
              <Card className="gap-0 overflow-hidden py-0">
                <div className="flex items-center gap-2 border-b px-4 py-2">
                  <div className="flex-1 text-sm font-semibold">
                    {tn('{count} scan waiting to be sent', '{count} scans waiting to be sent', offline.pending.length)}
                  </div>
                  {canWrite && (
                    <Button
                      variant="outline"
                      size="sm"
                      disabled={!offline.online || offline.syncing || offline.pending.every((scan) => scan.error)}
                      onClick={() => void offline.sync()}
                    >
                      <RefreshCw className={`size-3.5 ${offline.syncing ? 'animate-spin' : ''}`} />
                      {offline.syncing ? t('Sending…') : t('Send now')}
                    </Button>
                  )}
                </div>
                <div className="divide-y">
                  {offline.pending.map((scan) => (
                    <div key={scan.id} className="flex items-center gap-3 px-4 py-2.5">
                      {scan.kind === 'receipt' ? <PackageCheck className="size-4 shrink-0 text-muted-foreground" /> : <Clock className="size-4 shrink-0 text-muted-foreground" />}
                      <div className="min-w-0 flex-1">
                        <div className="truncate font-mono text-sm font-semibold">{scan.part_reference}</div>
                        <div className="truncate text-xs text-muted-foreground">{scan.location_name}</div>
                        {scan.error && (
                          <div className="text-xs text-red-600 dark:text-red-400">{t('Refused: {error}', { error: scan.error })}</div>
                        )}
                      </div>
                      <span className="shrink-0 font-mono text-xs text-muted-foreground">{formatAgo(scan.scanned_at)}</span>
                      <span
                        className={`shrink-0 font-mono text-xs font-semibold ${
                          scan.quantity > 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400'
                        }`}
                      >
                        {scan.quantity > 0 ? `+${scan.quantity}` : scan.quantity}
                      </span>
                      {scan.error && (
                        <Button
                          variant="ghost"
                          size="icon"
                          className="size-7 shrink-0"
                          aria-label={t('Discard')}
                          onClick={() => void offline.discard(scan.id)}
                        >
                          <Trash2 className="size-3.5" />
                        </Button>
                      )}
                    </div>
                  ))}
                </div>
              </Card>
            )}

            {/* Recent scans */}
            <Card className="gap-0 overflow-hidden py-0">
              <div className="border-b px-4 py-3 text-sm font-semibold">{t('Recent scans')}</div>
              {recent_scans.length === 0 ? (
                <div className="px-4 py-6 text-sm text-muted-foreground">
                  {t('Counts recorded from the scanner will appear here.')}
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
