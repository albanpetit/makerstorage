import { useEffect, useState } from 'react'
import { router } from '@inertiajs/react'
import { ArrowRight } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card'
import { Checkbox } from '@/components/ui/checkbox'
import { Label } from '@/components/ui/label'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog'

import type { OrganizationSettings } from './types'
import { t, tn } from '@/lib/i18n'

interface ReassignChange {
  id: number
  name: string
  from: string | null
  to: string | null
  takes_bag: boolean
}

interface ReassignPreview {
  total: number
  changed: number
  cleared: number
  changes: ReassignChange[]
}

interface ReassignIpnsCardProps {
  organization: OrganizationSettings
  formatChanged: boolean
}

// Renumber existing parts to the saved format, after a part-by-part preview of
// what changes. Disabled while the format has unsaved edits, since the server
// uses the saved settings.
export function ReassignIpnsCard({ organization, formatChanged }: ReassignIpnsCardProps) {
  const boxBag = organization.ipn_generation_mode === 'box_bag'
  const [open, setOpen] = useState(false)
  const [clearUnbagged, setClearUnbagged] = useState(false)
  const [preview, setPreview] = useState<ReassignPreview | null>(null)
  const [loadError, setLoadError] = useState('')
  const [reassigning, setReassigning] = useState(false)

  useEffect(() => {
    if (!open) return
    let cancelled = false
    setPreview(null)
    setLoadError('')
    fetch(`/settings/reassign_ipns_preview?clear_unbagged=${clearUnbagged}`, { headers: { Accept: 'application/json' } })
      .then((res) => {
        if (!res.ok) throw new Error('Failed to load preview')
        return res.json()
      })
      .then((body: ReassignPreview) => {
        if (!cancelled) setPreview(body)
      })
      .catch(() => {
        if (!cancelled) setLoadError(t('Could not load the preview. Please try again.'))
      })
    return () => {
      cancelled = true
    }
  }, [open, clearUnbagged])

  const reassignIpns = () => {
    router.post('/settings/reassign_ipns', { clear_unbagged: clearUnbagged }, {
      preserveScroll: true,
      onStart: () => setReassigning(true),
      onFinish: () => setReassigning(false),
    })
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('Reassign existing references')}</CardTitle>
        <CardDescription>
          {boxBag
            ? <>{t('Give every part the code of its bag. A part without a bag takes the bag its stock sits in, if no other part holds it; the others keep their reference, unless you choose to clear it.')}</>
            : tn(
              'Renumber every part with the current saved format. A format change only affects new parts — use this to bring the {count} existing part in line with it.',
              'Renumber every part with the current saved format. A format change only affects new parts — use this to bring the {count} existing parts in line with it.',
              organization.parts_count,
            )}
        </CardDescription>
      </CardHeader>
      <CardFooter className="flex-wrap justify-between gap-2 border-t">
        <p className="text-xs text-muted-foreground">
          {formatChanged
            ? t('Save your format changes first to renumber with them.')
            : t('You’ll see every change before anything is applied.')}
        </p>
        <AlertDialog open={open} onOpenChange={setOpen}>
          <AlertDialogTrigger asChild>
            <Button
              type="button"
              variant="outline"
              disabled={formatChanged || reassigning || organization.parts_count === 0}
            >
              {reassigning ? t('Reassigning…') : t('Preview & reassign')}
            </Button>
          </AlertDialogTrigger>
          <AlertDialogContent className="sm:max-w-2xl">
            <AlertDialogHeader>
              <AlertDialogTitle>{t('Reassign IPNs')}</AlertDialogTitle>
              <AlertDialogDescription>
                {preview == null
                  ? t('Working out what would change…')
                  : preview.changed === 0
                    ? tn('The part already has the right reference.', 'All {count} parts already have the right reference.', preview.total)
                    : <>
                        {tn('{changed} of {count} part will change.', '{changed} of {count} parts will change.', preview.total, { changed: preview.changed })}
                        {preview.cleared > 0 && <>{' '}{tn('{count} of them loses its reference.', '{count} of them lose their reference.', preview.cleared)}</>}
                        {' '}{t('This can’t be undone.')}
                      </>}
              </AlertDialogDescription>
            </AlertDialogHeader>

            {boxBag && (
              <div className="flex items-start gap-2">
                <Checkbox
                  id="clear-unbagged"
                  checked={clearUnbagged}
                  onCheckedChange={(checked) => setClearUnbagged(checked === true)}
                />
                <Label htmlFor="clear-unbagged" className="text-sm font-normal leading-snug">
                  {t('Clear the reference of parts that don’t get a bag, so only bag codes remain')}
                </Label>
              </div>
            )}

            {loadError && <p className="text-sm text-destructive">{loadError}</p>}
            {preview == null && !loadError && <Skeleton className="h-40 w-full" />}
            {preview != null && preview.changes.length > 0 && (
              <div className="max-h-72 overflow-y-auto rounded-md border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>{t('Part')}</TableHead>
                      <TableHead>{t('Current')}</TableHead>
                      <TableHead className="w-6" />
                      <TableHead>{t('New')}</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {preview.changes.map((change) => (
                      <TableRow key={change.id}>
                        <TableCell className="max-w-56 truncate">{change.name}</TableCell>
                        <TableCell className="font-mono text-muted-foreground">{change.from ?? '—'}</TableCell>
                        <TableCell><ArrowRight className="size-3.5 text-muted-foreground" /></TableCell>
                        <TableCell className="font-mono">
                          {change.to ?? <span className="font-sans text-destructive">{t('cleared')}</span>}
                          {change.takes_bag && <Badge variant="secondary" className="ml-2 font-sans">{t('takes bag')}</Badge>}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
            {preview != null && preview.changed > preview.changes.length && (
              <p className="text-xs text-muted-foreground">
                {t('Showing the first {shown} of {count} changes.', { shown: preview.changes.length, count: preview.changed })}
              </p>
            )}

            <AlertDialogFooter>
              <AlertDialogCancel>{t('Cancel')}</AlertDialogCancel>
              <AlertDialogAction onClick={reassignIpns} disabled={preview == null || preview.changed === 0}>
                {tn('Reassign {count} IPN', 'Reassign {count} IPNs', preview?.changed ?? 0)}
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </CardFooter>
    </Card>
  )
}
