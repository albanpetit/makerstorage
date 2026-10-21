import { Head, Link, router } from '@inertiajs/react'
import { useState } from 'react'
import { ArrowLeft, CheckCircle2, Combine, EyeOff } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { PartDetailSheet } from '@/components/part-detail-sheet'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Checkbox } from '@/components/ui/checkbox'
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

interface DuplicatePart {
  id: number
  name: string
  ipn: string | null
  mpn: string | null
  sku: string | null
  manufacturer: string | null
  value: string | null
  unit: string
  status: string
  category_name: string | null
  footprint_name: string | null
  total_quantity: number
  locations: { path: string; quantity: number }[]
  suppliers: string[]
  movements_count: number
  order_lines_count: number
  project_lines_count: number
  created_at: string
}

interface DuplicateGroup {
  key: string
  certain: boolean
  reasons: string[]
  parts: DuplicatePart[]
  suggested_keep_id: number
}

interface PartDuplicatesProps {
  groups: DuplicateGroup[]
  total_groups: number
  // Parts picked in the inventory list rather than found by the finder.
  manual: boolean
}

const plural = (count: number, word: string) => `${count.toLocaleString()} ${word}${count === 1 ? '' : 's'}`

export default function PartDuplicatesIndex({ groups, total_groups, manual }: PartDuplicatesProps) {
  const [detailPartId, setDetailPartId] = useState<number | null>(null)

  const subtitle = manual
    ? 'Pick the part to keep: the others are merged into it'
    : total_groups === 0
      ? 'Parts that look like the same component entered twice'
      : `${plural(total_groups, 'group')} of parts that look like the same component${total_groups > groups.length ? ` · showing the first ${groups.length}` : ''}`

  return (
    <AppLayout
      header={
        <PageHeader title={manual ? 'Merge parts' : 'Duplicates'} subtitle={subtitle}>
          <Button variant="outline" size="sm" asChild>
            <Link href="/parts">
              <ArrowLeft className="size-4" />
              Inventory
            </Link>
          </Button>
        </PageHeader>
      }
    >
      <Head title={manual ? 'Merge parts' : 'Duplicates'} />

      <div className="space-y-4">
        <FlashMessages />

        {groups.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-2 py-10 text-center">
              <CheckCircle2 className="size-8 text-emerald-500" />
              <div className="font-medium">{manual ? 'Nothing left to merge' : 'No duplicates found'}</div>
              <p className="max-w-md text-sm text-muted-foreground">
                Parts are paired when they share a part number (MPN, SKU, barcode or a supplier part number), or the
                same name, value and footprint. To merge parts the finder misses, select them in the inventory and
                choose Merge.
              </p>
            </CardContent>
          </Card>
        ) : (
          groups.map((group) => (
            <DuplicateGroupCard key={group.key} group={group} manual={manual} onShowPart={setDetailPartId} />
          ))
        )}
      </div>

      <PartDetailSheet
        partId={detailPartId}
        open={detailPartId !== null}
        onOpenChange={(open) => !open && setDetailPartId(null)}
      />
    </AppLayout>
  )
}

function DuplicateGroupCard({
  group, manual, onShowPart,
}: { group: DuplicateGroup; manual: boolean; onShowPart: (id: number) => void }) {
  const { canWrite } = usePermissions()
  const [keepId, setKeepId] = useState(group.suggested_keep_id)
  // Parts to fold into the kept one; a part that isn't a duplicate can be left out.
  const [included, setIncluded] = useState<number[]>(group.parts.map((part) => part.id))
  const [confirmOpen, setConfirmOpen] = useState(false)
  const [submitting, setSubmitting] = useState(false)

  const kept = group.parts.find((part) => part.id === keepId) ?? group.parts[0]
  const merged = group.parts.filter((part) => part.id !== kept.id && included.includes(part.id))
  const units = new Set([ kept, ...merged ].map((part) => part.unit))
  const unitClash = units.size > 1

  const totals = merged.reduce(
    (sum, part) => ({
      units: sum.units + part.total_quantity,
      movements: sum.movements + part.movements_count,
      orderLines: sum.orderLines + part.order_lines_count,
      projectLines: sum.projectLines + part.project_lines_count,
    }),
    { units: 0, movements: 0, orderLines: 0, projectLines: 0 },
  )
  const moved = [
    totals.units > 0 && `${plural(totals.units, 'unit')} of stock`,
    totals.movements > 0 && plural(totals.movements, 'movement'),
    totals.orderLines > 0 && plural(totals.orderLines, 'order line'),
    totals.projectLines > 0 && plural(totals.projectLines, 'project line'),
  ].filter(Boolean) as string[]

  const toggle = (id: number, checked: boolean) =>
    setIncluded((current) => (checked ? [ ...current, id ] : current.filter((other) => other !== id)))

  const visitOptions = {
    preserveScroll: true,
    onStart: () => setSubmitting(true),
    onFinish: () => setSubmitting(false),
    onSuccess: () => setConfirmOpen(false),
    onError: () => setConfirmOpen(false),
  }

  const merge = () => {
    router.post('/parts/duplicates/merge', {
      keep_id: kept.id,
      part_ids: merged.map((part) => part.id),
      ...(manual ? { return_to: 'parts' } : {}),
    }, visitOptions)
  }

  const dismiss = () => {
    router.post('/parts/duplicates/dismiss', { part_ids: group.parts.map((part) => part.id) }, visitOptions)
  }

  return (
    <Card className="gap-0 py-0">
      <div className="flex flex-col gap-x-3 gap-y-2 border-b px-4 py-3 sm:flex-row sm:items-center">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-medium">{kept.name}</span>
            {!manual && (
              group.certain
                ? <Badge className="border-transparent bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-400">Likely duplicates</Badge>
                : <Badge variant="outline">Possible duplicates</Badge>
            )}
          </div>
          {group.reasons.length > 0 && (
            <p className="mt-0.5 text-xs text-muted-foreground">{group.reasons.join(' · ')}</p>
          )}
        </div>
        {canWrite && (
          <div className="flex flex-wrap gap-2">
            {!manual && (
              <Button variant="ghost" size="sm" disabled={submitting} onClick={dismiss}>
                <EyeOff className="size-4" />
                Not duplicates
              </Button>
            )}
            <Button size="sm" disabled={submitting || merged.length === 0 || unitClash} onClick={() => setConfirmOpen(true)}>
              <Combine className="size-4" />
              Merge {merged.length > 0 ? plural(merged.length, 'part') : ''}
            </Button>
          </div>
        )}
      </div>

      {unitClash && (
        <p className="border-b bg-destructive/5 px-4 py-2 text-xs text-destructive">
          These parts are counted in different units ({[ ...units ].join(', ')}): leave out the ones that don't match.
        </p>
      )}

      <Table>
        <TableHeader>
          <TableRow>
            {canWrite && <TableHead className="w-10 pl-4"><span className="sr-only">Merge</span></TableHead>}
            <TableHead className={canWrite ? undefined : 'pl-4'}>Part</TableHead>
            <TableHead>Category · footprint</TableHead>
            <TableHead className="text-right">Stock</TableHead>
            <TableHead>History</TableHead>
            <TableHead>Suppliers</TableHead>
            {canWrite && <TableHead className="w-28 pr-4 text-right"><span className="sr-only">Keep</span></TableHead>}
          </TableRow>
        </TableHeader>
        <TableBody>
          {group.parts.map((part) => {
            const isKept = part.id === kept.id
            const isMerged = !isKept && included.includes(part.id)
            const ids = [ part.ipn, part.mpn, part.sku, part.manufacturer ].filter(Boolean).join(' · ')
            return (
              <TableRow key={part.id} data-state={isKept ? 'selected' : undefined} className={!isKept && !isMerged ? 'opacity-50' : undefined}>
                {canWrite && (
                  <TableCell className="pl-4">
                    <Checkbox
                      aria-label={`Merge ${part.name}`}
                      checked={isKept || isMerged}
                      disabled={isKept}
                      onCheckedChange={(checked) => toggle(part.id, checked === true)}
                    />
                  </TableCell>
                )}
                <TableCell className={`max-w-72 whitespace-normal ${canWrite ? '' : 'pl-4'}`}>
                  <Button variant="link" className="h-auto p-0 text-left font-medium" onClick={() => onShowPart(part.id)}>
                    {part.name}
                  </Button>
                  {ids && <div className="font-mono text-xs text-muted-foreground">{ids}</div>}
                  {part.status !== 'active' && <Badge variant="outline" className="mt-1 capitalize">{part.status}</Badge>}
                </TableCell>
                <TableCell className="text-sm">
                  <div>{part.category_name ?? '—'}</div>
                  <div className="text-xs text-muted-foreground">
                    {[ part.footprint_name, part.value ].filter(Boolean).join(' · ') || '—'}
                  </div>
                </TableCell>
                <TableCell className="text-right">
                  <div className="font-mono text-sm">{part.total_quantity.toLocaleString()}{part.unit !== 'piece' ? ` ${part.unit}` : ''}</div>
                  {part.locations.slice(0, 2).map((location) => (
                    <div key={location.path} className="text-xs text-muted-foreground">{location.path} ({location.quantity})</div>
                  ))}
                  {part.locations.length > 2 && <div className="text-xs text-muted-foreground">+{part.locations.length - 2} more</div>}
                </TableCell>
                <TableCell className="text-xs text-muted-foreground">
                  <div>{plural(part.movements_count, 'movement')}</div>
                  {(part.order_lines_count > 0 || part.project_lines_count > 0) && (
                    <div>
                      {[
                        part.order_lines_count > 0 && plural(part.order_lines_count, 'order line'),
                        part.project_lines_count > 0 && plural(part.project_lines_count, 'BOM line'),
                      ].filter(Boolean).join(' · ')}
                    </div>
                  )}
                  <div>Added {new Date(part.created_at).toLocaleDateString()}</div>
                </TableCell>
                <TableCell className="max-w-48 whitespace-normal text-xs text-muted-foreground">
                  {part.suppliers.length > 0 ? part.suppliers.join(', ') : '—'}
                </TableCell>
                {canWrite && (
                  <TableCell className="pr-4 text-right">
                    {isKept ? (
                      <Badge>Kept</Badge>
                    ) : (
                      <Button variant="outline" size="sm" onClick={() => { setKeepId(part.id); toggle(part.id, true) }}>
                        Keep this one
                      </Button>
                    )}
                  </TableCell>
                )}
              </TableRow>
            )
          })}
        </TableBody>
      </Table>

      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Merge {plural(merged.length, 'part')} into {kept.name}?</AlertDialogTitle>
            <AlertDialogDescription asChild>
              <div className="space-y-2">
                <p>
                  {[ ...moved, 'tags, supplier links and files' ].join(', ')} move to {kept.name}. It keeps its own
                  details; the ones it leaves blank are filled in from the others.
                </p>
                <p>Then {merged.map((part) => part.name).join(', ')} {merged.length === 1 ? 'is' : 'are'} deleted. This can't be undone.</p>
              </div>
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={submitting}>Cancel</AlertDialogCancel>
            <AlertDialogAction disabled={submitting} onClick={(event) => { event.preventDefault(); merge() }}>
              Merge
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Card>
  )
}
