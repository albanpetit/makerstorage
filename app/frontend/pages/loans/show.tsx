import { Head, Link, router } from '@inertiajs/react'
import { FormEvent, useState } from 'react'
import { ArrowLeft, Pencil, PackageCheck, Undo2, XCircle } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { LOAN_STATUS_META, formatDate, type LoanStatus } from '@/components/loans/types'
import { StorageLocationSelect, type StorageLocationOption } from '@/components/storage-location-select'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
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

interface LoanLine {
  id: number
  part: { id: number; reference: string; ipn: string | null; name: string }
  storage_location: { id: number; name: string } | null
  quantity: number
  returned_quantity: number
  lost_quantity: number
  outstanding: number
}

interface Loan {
  id: number
  reference: string | null
  borrower_name: string
  borrower_contact: string | null
  borrower_is_member: boolean
  lent_by_name: string | null
  status: LoanStatus
  due_on: string | null
  days_overdue: number
  notes: string | null
  created_at: string
  closed_at: string | null
  lines: LoanLine[]
}

interface LoanShowProps {
  loan: Loan
  storage_locations: StorageLocationOption[]
}

type SettleMode = 'return' | 'write_off'

export default function LoanShow({ loan, storage_locations }: LoanShowProps) {
  const { canWrite } = usePermissions()
  const open = loan.status !== 'returned'
  const meta = LOAN_STATUS_META[loan.status]
  const title = loan.reference ?? `Loan #${loan.id}`

  const [settle, setSettle] = useState<{ line: LoanLine; mode: SettleMode } | null>(null)
  const [quantity, setQuantity] = useState('1')
  const [locationId, setLocationId] = useState('')
  const [processing, setProcessing] = useState(false)
  const [returnAllOpen, setReturnAllOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [edit, setEdit] = useState({ due_on: '', borrower_contact: '', notes: '' })

  const startSettle = (line: LoanLine, mode: SettleMode) => {
    setQuantity(String(line.outstanding))
    setLocationId(line.storage_location ? String(line.storage_location.id) : '')
    setSettle({ line, mode })
  }

  const submitSettle = (e: FormEvent) => {
    e.preventDefault()
    if (!settle) return
    const options = {
      preserveScroll: true,
      onSuccess: () => setSettle(null),
      onFinish: () => setProcessing(false),
    }
    setProcessing(true)
    if (settle.mode === 'return') {
      router.post(`/loans/${loan.id}/return_items`, {
        lines: [{ line_id: settle.line.id, quantity, storage_location_id: locationId }],
      }, options)
    } else {
      router.post(`/loans/${loan.id}/write_off`, { line_id: settle.line.id, quantity }, options)
    }
  }

  const startEdit = () => {
    setEdit({ due_on: loan.due_on ?? '', borrower_contact: loan.borrower_contact ?? '', notes: loan.notes ?? '' })
    setEditOpen(true)
  }

  const submitEdit = (e: FormEvent) => {
    e.preventDefault()
    setProcessing(true)
    router.patch(`/loans/${loan.id}`, { loan: edit }, {
      preserveScroll: true,
      onSuccess: () => setEditOpen(false),
      onFinish: () => setProcessing(false),
    })
  }

  const outstanding = loan.lines.reduce((sum, line) => sum + line.outstanding, 0)

  return (
    <AppLayout
      header={
        <PageHeader title={title} subtitle={`Lent to ${loan.borrower_name}`}>
          <Button variant="outline" size="sm" asChild>
            <Link href="/loans">
              <ArrowLeft className="size-4" />
              Loans
            </Link>
          </Button>
          {canWrite && open && (
            <Button size="sm" onClick={() => setReturnAllOpen(true)}>
              <PackageCheck className="size-4" />
              Return everything
            </Button>
          )}
        </PageHeader>
      }
    >
      <Head title={title} />

      <div className="space-y-4">
        <FlashMessages />

        <Card>
          <CardContent className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <div>
              <div className="text-xs text-muted-foreground">Status</div>
              <div className="mt-1 flex items-center gap-2">
                <Badge variant="outline" className={meta.className}>{meta.label}</Badge>
                {loan.status === 'overdue' && (
                  <span className="text-sm font-medium text-destructive">
                    {loan.days_overdue} day{loan.days_overdue === 1 ? '' : 's'} late
                  </span>
                )}
              </div>
            </div>
            <div>
              <div className="text-xs text-muted-foreground">Borrower</div>
              <div className="mt-1 text-sm font-medium">
                {loan.borrower_name}
                {!loan.borrower_is_member && <span className="ml-1.5 text-xs font-normal text-muted-foreground">(not a member)</span>}
              </div>
              {loan.borrower_contact && <div className="truncate text-xs text-muted-foreground">{loan.borrower_contact}</div>}
            </div>
            <div>
              <div className="text-xs text-muted-foreground">Lent</div>
              <div className="mt-1 text-sm">{formatDate(loan.created_at)}</div>
              {loan.lent_by_name && <div className="text-xs text-muted-foreground">by {loan.lent_by_name}</div>}
            </div>
            <div>
              <div className="text-xs text-muted-foreground">{loan.closed_at ? 'Returned' : 'Due back'}</div>
              <div className="mt-1 flex items-center gap-1 text-sm">
                {loan.closed_at ? formatDate(loan.closed_at) : loan.due_on ? formatDate(loan.due_on) : 'No due date'}
                {canWrite && open && (
                  <Button variant="ghost" size="icon-sm" aria-label="Edit loan" onClick={startEdit}>
                    <Pencil className="size-3.5 text-muted-foreground" />
                  </Button>
                )}
              </div>
            </div>
            {loan.notes && (
              <div className="sm:col-span-2 lg:col-span-4">
                <div className="text-xs text-muted-foreground">Notes</div>
                <p className="mt-1 text-sm whitespace-pre-line">{loan.notes}</p>
              </div>
            )}
          </CardContent>
        </Card>

        <Card className="overflow-hidden py-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Item</TableHead>
                <TableHead>Taken from</TableHead>
                <TableHead className="text-right">Lent</TableHead>
                <TableHead className="text-right">Returned</TableHead>
                <TableHead className="text-right">Written off</TableHead>
                <TableHead className="text-right">Still out</TableHead>
                {canWrite && open && <TableHead className="w-0" />}
              </TableRow>
            </TableHeader>
            <TableBody>
              {loan.lines.map((line) => (
                <TableRow key={line.id}>
                  <TableCell>
                    <div className="font-medium">{line.part.name}</div>
                    <div className="font-mono text-xs text-muted-foreground">{line.part.ipn ?? line.part.reference}</div>
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground">{line.storage_location?.name ?? '—'}</TableCell>
                  <TableCell className="text-right font-mono">{line.quantity}</TableCell>
                  <TableCell className="text-right font-mono">{line.returned_quantity || '—'}</TableCell>
                  <TableCell className="text-right font-mono">{line.lost_quantity || '—'}</TableCell>
                  <TableCell className={`text-right font-mono font-semibold ${line.outstanding > 0 && loan.status === 'overdue' ? 'text-destructive' : ''}`}>
                    {line.outstanding}
                  </TableCell>
                  {canWrite && open && (
                    <TableCell>
                      {line.outstanding > 0 && (
                        <div className="flex justify-end gap-1">
                          <Button variant="outline" size="sm" onClick={() => startSettle(line, 'return')}>
                            <Undo2 className="size-4" />
                            Return
                          </Button>
                          <Button variant="ghost" size="sm" onClick={() => startSettle(line, 'write_off')}>
                            <XCircle className="size-4" />
                            Write off
                          </Button>
                        </div>
                      )}
                    </TableCell>
                  )}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Card>
      </div>

      {/* Return / write off one line */}
      <Dialog open={settle !== null} onOpenChange={(o) => !o && setSettle(null)}>
        <DialogContent className="sm:max-w-md">
          {settle && (
            <form onSubmit={submitSettle}>
              <DialogHeader>
                <DialogTitle>{settle.mode === 'return' ? 'Return' : 'Write off'} {settle.line.part.name}</DialogTitle>
                <DialogDescription>
                  {settle.mode === 'return'
                    ? 'The items go back into stock in the zone you pick.'
                    : "For items that won't come back (lost, broken, used up). They already left stock when lent, so stock doesn't change."}
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-4 py-4">
                <div className="space-y-2">
                  <Label htmlFor="settle-qty">Quantity</Label>
                  <Input
                    id="settle-qty"
                    type="number"
                    min={1}
                    max={settle.line.outstanding}
                    value={quantity}
                    onChange={(e) => setQuantity(e.target.value)}
                  />
                  <p className="text-xs text-muted-foreground">{settle.line.outstanding} still out.</p>
                </div>
                {settle.mode === 'return' && (
                  <div className="space-y-2">
                    <Label htmlFor="settle-zone">Return to</Label>
                    <StorageLocationSelect
                      id="settle-zone"
                      locations={storage_locations}
                      value={locationId}
                      onValueChange={setLocationId}
                      placeholder="Pick a zone"
                    />
                  </div>
                )}
              </div>
              <DialogFooter>
                <Button type="button" variant="outline" onClick={() => setSettle(null)}>Cancel</Button>
                <Button
                  type="submit"
                  variant={settle.mode === 'return' ? 'default' : 'destructive'}
                  disabled={processing || !(Number(quantity) > 0) || (settle.mode === 'return' && !locationId)}
                >
                  {settle.mode === 'return' ? 'Return' : 'Write off'}
                </Button>
              </DialogFooter>
            </form>
          )}
        </DialogContent>
      </Dialog>

      {/* Edit due date, contact, notes */}
      <Dialog open={editOpen} onOpenChange={setEditOpen}>
        <DialogContent className="sm:max-w-md">
          <form onSubmit={submitEdit}>
            <DialogHeader>
              <DialogTitle>Edit loan</DialogTitle>
              <DialogDescription>Extend the due date, or update the contact and notes.</DialogDescription>
            </DialogHeader>
            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="edit-due">Due back</Label>
                <Input id="edit-due" type="date" value={edit.due_on} onChange={(e) => setEdit({ ...edit, due_on: e.target.value })} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="edit-contact">Contact</Label>
                <Input id="edit-contact" value={edit.borrower_contact} maxLength={255} onChange={(e) => setEdit({ ...edit, borrower_contact: e.target.value })} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="edit-notes">Notes</Label>
                <Textarea id="edit-notes" rows={3} value={edit.notes} onChange={(e) => setEdit({ ...edit, notes: e.target.value })} />
              </div>
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setEditOpen(false)}>Cancel</Button>
              <Button type="submit" disabled={processing}>Save</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Return everything */}
      <AlertDialog open={returnAllOpen} onOpenChange={setReturnAllOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Return everything?</AlertDialogTitle>
            <AlertDialogDescription>
              The {outstanding} item{outstanding === 1 ? '' : 's'} still out go back into the zones they were taken from, and the loan closes.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={() => router.post(`/loans/${loan.id}/return_all`, {}, { preserveScroll: true })}>
              Return everything
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </AppLayout>
  )
}
