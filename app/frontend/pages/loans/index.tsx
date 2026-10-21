import { Head, Link, router } from '@inertiajs/react'
import { useState } from 'react'
import { HandHelping, Plus } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { LendDialog } from '@/components/loans/lend-dialog'
import { LOAN_STATUS_META, formatDate, type LendablePart, type LoanStatus, type MemberOption } from '@/components/loans/types'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Switch } from '@/components/ui/switch'
import { Label } from '@/components/ui/label'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { t, tn } from '@/lib/i18n'

type Filter = 'open' | 'overdue' | 'returned' | 'all'

interface LoanSummary {
  id: number
  reference: string | null
  borrower_name: string
  mine: boolean
  status: LoanStatus
  due_on: string | null
  days_overdue: number
  created_at: string
  closed_at: string | null
  item_count: number
  outstanding: number
  items: string[]
  more_items: number
}

interface LoansPageProps {
  loans: LoanSummary[]
  filter: Filter
  mine: boolean
  counts: { open: number; overdue: number; returned: number }
  members: MemberOption[]
  parts: LendablePart[]
  default_due_on: string
  prefill_part_id: number | null
}

const FILTERS: { value: Filter; label: string }[] = [
  { value: 'open', get label() { return t('Out') } },
  { value: 'overdue', get label() { return t('Overdue') } },
  { value: 'returned', get label() { return t('Returned') } },
  { value: 'all', get label() { return t('All') } },
]

export default function LoansIndex({ loans, filter, mine, counts, members, parts, default_due_on, prefill_part_id }: LoansPageProps) {
  const { canWrite } = usePermissions()
  const [lendOpen, setLendOpen] = useState(canWrite && prefill_part_id != null)
  const [dialogKey, setDialogKey] = useState(0)

  const visit = (next: { filter?: Filter; mine?: boolean }) => {
    const params: Record<string, string> = { filter: next.filter ?? filter }
    if (next.mine ?? mine) params.mine = '1'
    router.get('/loans', params, { preserveScroll: true, preserveState: true })
  }

  const openLend = () => {
    setDialogKey((k) => k + 1)
    setLendOpen(true)
  }

  const countFor = (value: Filter) => (value === 'all' ? null : counts[value])

  return (
    <AppLayout
      header={
        <PageHeader title={t('Loans')} subtitle={t('Tools and parts lent to members, and when they\'re due back')}>
          {canWrite && (
            <Button size="sm" onClick={openLend}>
              <Plus className="size-4" />
              {t('Lend items')}
            </Button>
          )}
        </PageHeader>
      }
    >
      <Head title={t('Loans')} />

      <div className="space-y-4">
        <FlashMessages />

        <div className="flex flex-wrap items-center gap-3">
          <div className="flex flex-wrap gap-1 rounded-lg bg-muted p-1">
            {FILTERS.map((option) => {
              const count = countFor(option.value)
              return (
                <Button
                  key={option.value}
                  type="button"
                  size="sm"
                  variant={filter === option.value ? 'default' : 'ghost'}
                  onClick={() => visit({ filter: option.value })}
                >
                  {option.label}
                  {count != null && count > 0 && (
                    <span className={option.value === 'overdue' && filter !== 'overdue' ? 'text-destructive' : 'opacity-70'}>{count}</span>
                  )}
                </Button>
              )
            })}
          </div>
          <div className="flex items-center gap-2">
            <Switch id="loans-mine" checked={mine} onCheckedChange={(checked) => visit({ mine: checked })} />
            <Label htmlFor="loans-mine" className="text-sm font-normal">{t('Borrowed by me')}</Label>
          </div>
        </div>

        {loans.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
              <div className="flex size-11 items-center justify-center rounded-xl bg-muted text-muted-foreground">
                <HandHelping className="size-[22px]" />
              </div>
              <p className="font-semibold">{filter === 'overdue' ? t('Nothing overdue') : t('No loans here')}</p>
              <p className="max-w-sm text-sm text-muted-foreground">
                {t('Lend a tool or a few parts to a member: they leave stock until they\'re returned, and overdue loans are flagged here and in the email digest.')}
              </p>
            </CardContent>
          </Card>
        ) : (
          <Card className="overflow-hidden py-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t('Loan')}</TableHead>
                  <TableHead>{t('Borrower')}</TableHead>
                  <TableHead>{t('Items')}</TableHead>
                  <TableHead>{t('Lent')}</TableHead>
                  <TableHead>{t('Due')}</TableHead>
                  <TableHead>{t('Status')}</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {loans.map((loan) => {
                  const meta = LOAN_STATUS_META[loan.status]
                  return (
                    <TableRow key={loan.id} className="cursor-pointer" onClick={() => router.visit(`/loans/${loan.id}`)}>
                      <TableCell className="font-mono text-xs">
                        <Link href={`/loans/${loan.id}`} className="hover:underline" onClick={(e) => e.stopPropagation()}>
                          {loan.reference ?? `#${loan.id}`}
                        </Link>
                      </TableCell>
                      <TableCell className="font-medium">
                        {loan.borrower_name}
                        {loan.mine && <span className="ml-1.5 text-xs font-normal text-muted-foreground">{t('(you)')}</span>}
                      </TableCell>
                      <TableCell className="max-w-xs text-sm">
                        <div className="truncate">{loan.items.join(', ')}{loan.more_items > 0 && ` +${loan.more_items}`}</div>
                        {loan.status !== 'returned' && loan.outstanding < loan.item_count && (
                          <div className="text-xs text-muted-foreground">{t('{outstanding} of {total} still out', { outstanding: loan.outstanding, total: loan.item_count })}</div>
                        )}
                      </TableCell>
                      <TableCell className="text-xs text-muted-foreground">{formatDate(loan.created_at)}</TableCell>
                      <TableCell className={`text-xs ${loan.status === 'overdue' ? 'font-medium text-destructive' : 'text-muted-foreground'}`}>
                        {loan.due_on ? formatDate(loan.due_on) : '—'}
                        {loan.status === 'overdue' && <div>{tn('{count} day late', '{count} days late', loan.days_overdue)}</div>}
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline" className={meta.className}>{meta.label}</Badge>
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </Card>
        )}
      </div>

      {canWrite && (
        <LendDialog
          key={dialogKey}
          open={lendOpen}
          onOpenChange={setLendOpen}
          members={members}
          parts={parts}
          defaultDueOn={default_due_on}
          initialPartId={dialogKey === 0 ? prefill_part_id : null}
        />
      )}
    </AppLayout>
  )
}
