import { Head, Link, router } from '@inertiajs/react'
import { FormEvent, useState } from 'react'
import { CheckCircle2, ClipboardCheck, Clock, Plus } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { StorageLocationSelect, type StorageLocationOption } from '@/components/storage-location-select'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Textarea } from '@/components/ui/textarea'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

interface StocktakeSummary {
  id: number
  reference: string | null
  status: 'in_progress' | 'completed'
  zone_name: string
  include_sub_zones: boolean
  line_count: number
  counted_count: number
  discrepancy_count: number
  started_by: string | null
  created_at: string
  completed_at: string | null
}

interface DueZone {
  id: number
  name: string
  code: string | null
  location_type: string
  parts_count: number
  total_quantity: number
  last_counted_at: string | null
}

interface StocktakesPageProps {
  stocktakes: StocktakeSummary[]
  due_zones: DueZone[]
  due_after: number
  due_after_options: number[]
  storage_locations: StorageLocationOption[]
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, { day: '2-digit', month: '2-digit', year: 'numeric' })
}

export default function StocktakesIndex({ stocktakes, due_zones, due_after, due_after_options, storage_locations }: StocktakesPageProps) {
  const { canWrite } = usePermissions()
  const [open, setOpen] = useState(false)
  const [zoneId, setZoneId] = useState('')
  const [includeSubZones, setIncludeSubZones] = useState(true)
  const [blind, setBlind] = useState(false)
  const [notes, setNotes] = useState('')
  const [processing, setProcessing] = useState(false)

  const openDialog = (zone?: number) => {
    setZoneId(zone ? String(zone) : '')
    setIncludeSubZones(true)
    setBlind(false)
    setNotes('')
    setOpen(true)
  }

  const start = (e: FormEvent) => {
    e.preventDefault()
    if (!zoneId) return
    router.post('/stocktakes', {
      stocktake: { storage_location_id: zoneId, include_sub_zones: includeSubZones, blind, notes },
    }, {
      onStart: () => setProcessing(true),
      onFinish: () => setProcessing(false),
      onSuccess: () => setOpen(false),
    })
  }

  const inProgress = stocktakes.filter((s) => s.status === 'in_progress')

  return (
    <AppLayout
      header={
        <PageHeader title="Stocktakes" subtitle="Count a zone, review the differences, and correct the stock">
          {canWrite && (
            <Button size="sm" onClick={() => openDialog()}>
              <Plus className="size-4" />
              New stocktake
            </Button>
          )}
        </PageHeader>
      }
    >
      <Head title="Stocktakes" />

      <div className="space-y-6">
        <FlashMessages />

        {/* Zones due for a count */}
        <Card className="gap-0 overflow-hidden py-0">
          <div className="flex flex-wrap items-center gap-x-3 gap-y-2 border-b px-4 py-3">
            <div className="flex items-center gap-2 text-sm font-semibold">
              <Clock className="size-4 text-muted-foreground" />
              Zones due for a count
            </div>
            <span className="text-xs text-muted-foreground">Zones holding stock that no stocktake covered in the last</span>
            <Select
              value={String(due_after)}
              onValueChange={(value) => router.get('/stocktakes', { due_after: value }, { preserveScroll: true, preserveState: true })}
            >
              <SelectTrigger size="sm" className="w-28" aria-label="Due after"><SelectValue /></SelectTrigger>
              <SelectContent>
                {due_after_options.map((days) => (
                  <SelectItem key={days} value={String(days)}>{days} days</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          {due_zones.length === 0 ? (
            <CardContent className="flex items-center gap-2 px-4 py-6 text-sm text-muted-foreground">
              <CheckCircle2 className="size-4 text-emerald-600 dark:text-emerald-400" />
              Every zone holding stock was counted in the last {due_after} days.
            </CardContent>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Zone</TableHead>
                  <TableHead className="text-right">Parts</TableHead>
                  <TableHead className="text-right">Units</TableHead>
                  <TableHead>Last counted</TableHead>
                  <TableHead className="w-10" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {due_zones.map((zone) => (
                  <TableRow key={zone.id}>
                    <TableCell>
                      <div className="font-medium">{zone.name}</div>
                      {zone.code && <div className="font-mono text-xs text-muted-foreground">{zone.code}</div>}
                    </TableCell>
                    <TableCell className="text-right font-mono">{zone.parts_count}</TableCell>
                    <TableCell className="text-right font-mono">{zone.total_quantity.toLocaleString()}</TableCell>
                    <TableCell className="text-xs text-muted-foreground">
                      {zone.last_counted_at ? formatDate(zone.last_counted_at) : 'Never'}
                    </TableCell>
                    <TableCell>
                      {canWrite && (
                        <Button size="sm" variant="outline" onClick={() => openDialog(zone.id)}>
                          <ClipboardCheck className="size-4" />
                          Count
                        </Button>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </Card>

        {/* Stocktakes */}
        {stocktakes.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
              <div className="flex size-11 items-center justify-center rounded-xl bg-muted text-muted-foreground">
                <ClipboardCheck className="size-[22px]" />
              </div>
              <p className="font-semibold">No stocktakes yet</p>
              <p className="max-w-sm text-sm text-muted-foreground">
                Pick a drawer, shelf or cabinet and count what's really there, by hand or with the scanner. Completing the count corrects the stock with adjustment movements and keeps the report.
              </p>
            </CardContent>
          </Card>
        ) : (
          <Card className="overflow-hidden py-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Reference</TableHead>
                  <TableHead>Zone</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Counted</TableHead>
                  <TableHead className="text-right">Differences</TableHead>
                  <TableHead>Started</TableHead>
                  <TableHead>Completed</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {stocktakes.map((stocktake) => (
                  <TableRow key={stocktake.id} className="cursor-pointer" onClick={() => router.visit(`/stocktakes/${stocktake.id}`)}>
                    <TableCell className="font-mono text-sm font-medium">
                      <Link href={`/stocktakes/${stocktake.id}`} className="hover:underline" onClick={(e) => e.stopPropagation()}>
                        {stocktake.reference}
                      </Link>
                    </TableCell>
                    <TableCell>
                      <div>{stocktake.zone_name}</div>
                      {stocktake.include_sub_zones && <div className="text-xs text-muted-foreground">with sub-zones</div>}
                    </TableCell>
                    <TableCell>
                      {stocktake.status === 'in_progress' ? (
                        <Badge variant="outline" className="bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-400">In progress</Badge>
                      ) : (
                        <Badge variant="outline" className="bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400">Completed</Badge>
                      )}
                    </TableCell>
                    <TableCell className="text-right font-mono">{stocktake.counted_count} / {stocktake.line_count}</TableCell>
                    <TableCell className={`text-right font-mono ${stocktake.discrepancy_count > 0 ? 'text-amber-600 dark:text-amber-400' : ''}`}>
                      {stocktake.discrepancy_count}
                    </TableCell>
                    <TableCell className="text-xs text-muted-foreground">
                      {formatDate(stocktake.created_at)}
                      {stocktake.started_by && <div>{stocktake.started_by}</div>}
                    </TableCell>
                    <TableCell className="text-xs text-muted-foreground">
                      {stocktake.completed_at ? formatDate(stocktake.completed_at) : '—'}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </Card>
        )}
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-md">
          <form onSubmit={start}>
            <DialogHeader>
              <DialogTitle>New stocktake</DialogTitle>
              <DialogDescription>
                Lists every part the ledger has in the zone, ready to count. Nothing changes in stock until you complete the stocktake.
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="stocktake-zone">Zone to count</Label>
                <StorageLocationSelect
                  id="stocktake-zone"
                  locations={storage_locations}
                  value={zoneId}
                  onValueChange={setZoneId}
                  placeholder="Pick a zone"
                />
              </div>

              <div className="flex items-center justify-between gap-4">
                <div>
                  <Label htmlFor="stocktake-sub-zones">Include sub-zones</Label>
                  <p className="text-xs text-muted-foreground">Count the drawers and boxes inside it too.</p>
                </div>
                <Switch id="stocktake-sub-zones" checked={includeSubZones} onCheckedChange={setIncludeSubZones} />
              </div>

              <div className="flex items-center justify-between gap-4">
                <div>
                  <Label htmlFor="stocktake-blind">Blind count</Label>
                  <p className="text-xs text-muted-foreground">Hide the expected quantity until a line is counted.</p>
                </div>
                <Switch id="stocktake-blind" checked={blind} onCheckedChange={setBlind} />
              </div>

              <div className="space-y-2">
                <Label htmlFor="stocktake-notes">Notes</Label>
                <Textarea id="stocktake-notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Optional" rows={2} />
              </div>

              {inProgress.length > 0 && (
                <p className="text-xs text-muted-foreground">
                  {inProgress.length} stocktake{inProgress.length !== 1 ? 's are' : ' is'} still in progress: a zone can't be in two counts at once.
                </p>
              )}
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={processing || !zoneId}>
                <ClipboardCheck className="size-4" />
                Start counting
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </AppLayout>
  )
}
