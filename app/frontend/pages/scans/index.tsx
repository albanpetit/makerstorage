import { Head, Link, router } from '@inertiajs/react'
import { FormEvent, useEffect, useMemo, useRef, useState } from 'react'
import { Box, Camera, CameraOff, Check, Cpu, ExternalLink, MapPin, ScanLine } from 'lucide-react'
import type { IScannerControls } from '@zxing/browser'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { PartDetailSheet } from '@/components/part-detail-sheet'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'

interface ScanLocationOption {
  id: number
  name: string
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
}

type ScanResult =
  | { kind: 'part'; part: ScannedPart }
  | { kind: 'location'; location: ScannedZone }
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

// Symbologies we read: QR (zones) plus the common 1D/2D barcodes on part labels.
const SCAN_FORMATS = [
  'qr_code', 'data_matrix', 'code_128', 'code_39',
  'ean_13', 'ean_8', 'upc_a', 'upc_e', 'itf', 'codabar',
] as const

// Minimal shape of the browser-native BarcodeDetector (not yet in TS DOM libs).
interface DetectedBarcode {
  rawValue: string
}
interface BarcodeDetectorInstance {
  detect(source: CanvasImageSource): Promise<DetectedBarcode[]>
}
interface BarcodeDetectorConstructor {
  new (options?: { formats?: string[] }): BarcodeDetectorInstance
  getSupportedFormats?(): Promise<string[]>
}

function describeCameraError(err: unknown): string {
  const e = err as { name?: string; message?: string }
  if (e?.name === 'NotAllowedError' || e?.name === 'SecurityError') {
    return 'Camera permission was denied. Allow camera access in your browser and try again.'
  }
  if (e?.name === 'NotFoundError' || e?.name === 'OverconstrainedError' || e?.name === 'DevicesNotFoundError') {
    return 'No camera was found on this device.'
  }
  if (e?.name === 'NotReadableError' || e?.name === 'TrackStartError') {
    return 'The camera is already in use by another application.'
  }
  return e?.message || 'Could not start the camera.'
}

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

export default function ScansIndex({ code, result, recent_scans, today_count, allow_negative_stock, errors }: ScanPageProps) {
  const { canWrite } = usePermissions()
  const [codeInput, setCodeInput] = useState('')
  const [delta, setDelta] = useState(0)
  const [locationId, setLocationId] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [detailPartId, setDetailPartId] = useState<number | null>(null)

  const videoRef = useRef<HTMLVideoElement>(null)
  const controlsRef = useRef<IScannerControls | null>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const rafRef = useRef<number | null>(null)
  // Guards against firing multiple lookups from rapid consecutive detections.
  const scannedRef = useRef(false)
  const [cameraActive, setCameraActive] = useState(false)
  const [cameraStarting, setCameraStarting] = useState(false)
  const [cameraError, setCameraError] = useState<string | null>(null)

  const stopCamera = () => {
    if (rafRef.current != null) {
      cancelAnimationFrame(rafRef.current)
      rafRef.current = null
    }
    controlsRef.current?.stop()
    controlsRef.current = null
    streamRef.current?.getTracks().forEach((track) => track.stop())
    streamRef.current = null
    if (videoRef.current) videoRef.current.srcObject = null
    setCameraActive(false)
  }

  const handleDecoded = (text: string) => {
    const trimmed = text.trim()
    if (!trimmed || scannedRef.current) return
    scannedRef.current = true
    stopCamera()
    router.get('/scan', { code: trimmed }, { preserveState: true, preserveScroll: true })
  }

  const startCamera = async () => {
    setCameraError(null)
    if (!navigator.mediaDevices?.getUserMedia) {
      setCameraError(
        window.isSecureContext
          ? 'This browser does not support camera access.'
          : 'Camera access requires HTTPS. Open the app over https:// (or on localhost) to scan.',
      )
      return
    }
    setCameraStarting(true)
    setCameraActive(true)
    scannedRef.current = false

    const BarcodeDetectorCtor = (window as unknown as { BarcodeDetector?: BarcodeDetectorConstructor }).BarcodeDetector

    try {
      if (BarcodeDetectorCtor) {
        // Preferred path: the browser-native detector (Chrome/Android/Edge) is
        // far faster and more reliable than decoding every frame in JS.
        const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } })
        streamRef.current = stream
        const video = videoRef.current!
        video.srcObject = stream
        await video.play()

        const supported = (await BarcodeDetectorCtor.getSupportedFormats?.()) ?? []
        const formats = SCAN_FORMATS.filter((f) => supported.length === 0 || supported.includes(f))
        const detector = new BarcodeDetectorCtor(formats.length ? { formats: [ ...formats ] } : undefined)

        const scan = async () => {
          if (scannedRef.current || !streamRef.current) return
          try {
            const codes = await detector.detect(video)
            if (codes.length > 0 && codes[0].rawValue) {
              handleDecoded(codes[0].rawValue)
              return
            }
          } catch {
            // Transient decode errors (e.g. a not-yet-ready frame) — keep going.
          }
          rafRef.current = requestAnimationFrame(scan)
        }
        rafRef.current = requestAnimationFrame(scan)
      } else {
        // Fallback (Safari/Firefox): ZXing, restricted to the formats we use so
        // it locks on faster than scanning for every possible symbology.
        const [{ BrowserMultiFormatReader }, { DecodeHintType, BarcodeFormat }] = await Promise.all([
          import('@zxing/browser'),
          import('@zxing/library'),
        ])
        const hints = new Map([
          [ DecodeHintType.POSSIBLE_FORMATS, [
            BarcodeFormat.QR_CODE, BarcodeFormat.DATA_MATRIX, BarcodeFormat.CODE_128,
            BarcodeFormat.CODE_39, BarcodeFormat.EAN_13, BarcodeFormat.EAN_8,
            BarcodeFormat.UPC_A, BarcodeFormat.UPC_E, BarcodeFormat.ITF, BarcodeFormat.CODABAR,
          ] ],
        ])
        const reader = new BrowserMultiFormatReader(hints)
        controlsRef.current = await reader.decodeFromConstraints(
          { video: { facingMode: 'environment' } },
          videoRef.current!,
          (decoded) => {
            if (decoded) handleDecoded(decoded.getText())
          },
        )
      }
    } catch (err) {
      stopCamera()
      setCameraError(describeCameraError(err))
    } finally {
      setCameraStarting(false)
    }
  }

  // Always release the camera when leaving the page.
  useEffect(() => () => stopCamera(), [])

  useEffect(() => {
    setDelta(0)
    setLocationId('')
  }, [code])

  const part = result?.kind === 'part' ? result.part : null
  const selectedLocation = useMemo(() => {
    if (!part) return null
    return part.locations.find((location) => String(location.id) === locationId) ?? part.locations[0] ?? null
  }, [part, locationId])

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

  const matchLabel = !result ? '—' : result.kind === 'part' ? 'Part' : result.kind === 'location' ? 'Zone' : 'Unknown'

  return (
    <AppLayout
      header={
        <PageHeader title="Scanner" subtitle="Scan a QR code to locate a zone or count a component">
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
                ref={videoRef}
                className={`absolute inset-0 size-full object-cover transition-opacity ${cameraActive ? 'opacity-100' : 'opacity-0'}`}
                muted
                playsInline
              />

              {/* Framing overlay — only meaningful while the camera is live */}
              {cameraActive && (
                <div className="absolute inset-[14%]">
                  <div className="absolute top-0 left-0 size-8 rounded-tl-lg border-t-[3px] border-l-[3px] border-primary" />
                  <div className="absolute top-0 right-0 size-8 rounded-tr-lg border-t-[3px] border-r-[3px] border-primary" />
                  <div className="absolute bottom-0 left-0 size-8 rounded-bl-lg border-b-[3px] border-l-[3px] border-primary" />
                  <div className="absolute right-0 bottom-0 size-8 rounded-br-lg border-r-[3px] border-b-[3px] border-primary" />
                  <div className="absolute inset-x-[6%] h-0.5 animate-[scan-line_2.6s_ease-in-out_infinite] bg-gradient-to-r from-transparent via-primary to-transparent shadow-[0_0_12px_2px_var(--primary)]" />
                </div>
              )}

              {/* Idle state — ghost QR + start button */}
              {!cameraActive && (
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
                    <Button type="button" onClick={startCamera} disabled={cameraStarting} className="h-10">
                      <Camera className="size-4" />
                      {cameraStarting ? 'Starting camera…' : 'Start camera'}
                    </Button>
                    <span className="text-xs text-zinc-400">…or use a hardware scanner / type a code below</span>
                  </div>
                </>
              )}

              {/* Stop control while live */}
              {cameraActive && (
                <button
                  type="button"
                  onClick={stopCamera}
                  className="absolute top-2.5 right-2.5 inline-flex items-center gap-1.5 rounded-lg border border-white/20 bg-black/40 px-2.5 py-1.5 text-xs font-medium text-white backdrop-blur transition-colors hover:bg-black/60"
                >
                  <CameraOff className="size-3.5" />
                  Stop
                </button>
              )}
            </div>

            {cameraError && (
              <div className="mt-3 rounded-lg border border-red-900/50 bg-red-950/40 px-3 py-2 text-xs text-red-300">
                {cameraError}
              </div>
            )}

            <form onSubmit={submitScan} className="mt-3.5 space-y-2">
              <Input
                value={codeInput}
                onChange={(e) => setCodeInput(e.target.value)}
                placeholder="Barcode, SKU, MPN, or zone code…"
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
                      <Select
                        value={String(selectedLocation?.id ?? '')}
                        onValueChange={setLocationId}
                      >
                        <SelectTrigger className="w-full">
                          <SelectValue placeholder="Select a location" />
                        </SelectTrigger>
                        <SelectContent>
                          {part.locations.map((location) => (
                            <SelectItem key={location.id} value={String(location.id)}>
                              {location.name} · {location.quantity.toLocaleString()}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
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
                  <Button variant="outline" className="mt-4 w-full" asChild>
                    <Link href="/storage_locations">
                      <Box className="size-4" />
                      Open storage zones
                    </Link>
                  </Button>
                </CardContent>
              </Card>
            )}

            {result?.kind === 'unknown' && code && (
              <Card className="gap-0 overflow-hidden py-0">
                <ResultCardHeader tone="error" label="✗ Unknown code" code={code} />
                <CardContent className="px-4 py-5 text-sm text-muted-foreground">
                  No part or storage zone matches this code. Codes are matched against part barcodes, SKUs, MPNs, and zone codes.
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
                    The scanned component or zone will appear here with its quick actions.
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
