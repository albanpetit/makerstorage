import { Head, router, useForm } from '@inertiajs/react'
import { FormEvent, useState } from 'react'
import { toast } from 'sonner'
import { Plus, Download, ArrowDown, ArrowUp, ArrowLeftRight, Package, Filter, ChevronLeft, ChevronRight } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { StorageLocationSelect, type StorageLocationOption } from '@/components/storage-location-select'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { t, intlLocale, tn } from '@/lib/i18n'
import { formatQuantity, sumQuantities } from '@/lib/quantity'
import { QuantityInput } from '@/components/quantity-input'

type MovementFilter = 'all' | Movement['movement_type']

interface Pagination {
  page: number
  page_count: number
  total: number
  page_size: number
}

interface MovementStats {
  inbound: number
  outbound: number
  total: number
  in_count: number
  out_count: number
  adjustment_count: number
}

interface MovementPart {
  id: number
  reference: string
  name: string
  unit: string
  category: { name: string; color: string | null } | null
}

interface Movement {
  id: number
  created_at: string
  movement_type: 'in' | 'out' | 'adjustment'
  quantity_delta: number
  reason: string | null
  balance_after: number
  user_name: string | null
  location_name: string
  part: MovementPart
}

interface PartOption {
  id: number
  reference: string
  name: string
  unit: string
  pack_size: number | null
}

interface StockMovementsPageProps {
  movements: Movement[]
  pagination: Pagination
  filter: MovementFilter
  stats: MovementStats
  parts: PartOption[]
  storage_locations: StorageLocationOption[]
}

const TYPE_META: Record<Movement['movement_type'], { label: string; className: string }> = {
  in: { get label() { return t('In') }, className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
  out: { get label() { return t('Out') }, className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
  adjustment: { get label() { return t('Adjustment') }, className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
}

function formatDateTime(iso: string) {
  const d = new Date(iso)
  return {
    date: d.toLocaleDateString(intlLocale(), { day: '2-digit', month: '2-digit', year: 'numeric' }),
    time: d.toLocaleTimeString(intlLocale(), { hour: '2-digit', minute: '2-digit' }),
  }
}

interface MovementFormData {
  stock_movement: {
    part_id: string
    storage_location_id: string
    movement_type: 'in' | 'out' | 'adjustment'
    direction: 'increase' | 'decrease'
    quantity: string
    reason: string
  }
}

export default function StockMovementsIndex({ movements, pagination, filter, stats, parts, storage_locations }: StockMovementsPageProps) {
  const { canWrite } = usePermissions()
  const [newOpen, setNewOpen] = useState(false)

  // Filtering and paging are driven by the server: navigate with the desired
  // type/page and Inertia swaps in the matching page, stats, and counts.
  const navigate = (next: { type?: MovementFilter; page?: number }) => {
    const type = next.type ?? filter
    const page = next.page ?? pagination.page
    const query: Record<string, string | number> = {}
    if (type !== 'all') query.type = type
    if (page > 1) query.page = page
    router.get('/stock_movements', query, {
      preserveScroll: true,
      preserveState: true,
      only: [ 'movements', 'pagination', 'filter', 'stats' ],
    })
  }

  const exportCsv = () => {
    const query = filter !== 'all' ? `?type=${filter}` : ''
    window.location.href = `/stock_movements/export${query}`
  }

  const newForm = useForm<MovementFormData>({
    stock_movement: {
      part_id: '',
      storage_location_id: '',
      movement_type: 'in',
      direction: 'increase',
      quantity: '',
      reason: '',
    },
  })

  const openNewDialog = () => {
    newForm.reset()
    newForm.clearErrors()
    setNewOpen(true)
  }

  const submitNew = (e: FormEvent) => {
    e.preventDefault()
    newForm.post('/stock_movements', {
      preserveScroll: true,
      onSuccess: () => setNewOpen(false),
    })
  }

  const net = sumQuantities([ stats.inbound, -stats.outbound ])
  const selectedPart = parts.find((part) => String(part.id) === newForm.data.stock_movement.part_id)
  const statCards = [
    { label: t('Inbound'), value: `+${formatQuantity(stats.inbound)}`, icon: ArrowDown, className: 'text-emerald-600 dark:text-emerald-400' },
    { label: t('Outbound'), value: `−${formatQuantity(stats.outbound)}`, icon: ArrowUp, className: 'text-red-600 dark:text-red-400' },
    { label: t('Net balance'), value: `${net >= 0 ? '+' : ''}${formatQuantity(net)}`, icon: ArrowLeftRight, className: '' },
    { label: t('Movements'), value: stats.total.toLocaleString(intlLocale()), icon: Package, className: '' },
  ]

  const tabs = [
    { value: 'all' as const, label: t('All'), count: stats.total },
    { value: 'in' as const, label: t('Inbound'), count: stats.in_count },
    { value: 'out' as const, label: t('Outbound'), count: stats.out_count },
    { value: 'adjustment' as const, label: t('Adjustments'), count: stats.adjustment_count },
  ]

  const soonFilters = () => {
    toast.info(t('Advanced filters coming soon'), { description: t('Period, project, and user filters aren\'t wired up yet.') })
  }

  return (
    <AppLayout
      header={
        <PageHeader title={t('Movements')} subtitle={t('Inbound, outbound, and adjustments')}>
          <Button variant="outline" size="sm" onClick={exportCsv}>
            <Download className="size-4" />
            {t('Export CSV')}
          </Button>
          {canWrite && (
            <Button size="sm" onClick={openNewDialog}>
              <Plus className="size-4" />
              {t('New Movement')}
            </Button>
          )}
        </PageHeader>
      }
    >
      <Head title={t('Movements')} />

      <div className="space-y-6">
        <FlashMessages />

        {/* Stats */}
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          {statCards.map((stat) => (
            <Card key={stat.label}>
              <CardContent className="flex items-center justify-between">
                <div>
                  <div className="text-sm text-muted-foreground">{stat.label}</div>
                  <div className={`mt-1 font-mono text-2xl font-bold ${stat.className}`}>{stat.value}</div>
                </div>
                <stat.icon className="size-5 text-muted-foreground" />
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Filter tabs */}
        <div className="flex flex-wrap items-center gap-2">
          {tabs.map((tab) => (
            <Button
              key={tab.value}
              variant="ghost"
              onClick={() => navigate({ type: tab.value, page: 1 })}
              className={`h-8 gap-1.5 border px-3 ${
                filter === tab.value
                  ? 'border-foreground bg-foreground text-background hover:bg-foreground/90 hover:text-background dark:hover:bg-foreground/90'
                  : 'border-border bg-background'
              }`}
            >
              {tab.label}
              <span className="font-mono opacity-60">{tab.count}</span>
            </Button>
          ))}
          <div className="flex-1" />
          <Button
            variant="ghost"
            onClick={soonFilters}
            className="h-8 gap-1.5 border border-dashed px-3 font-normal text-muted-foreground has-[>svg]:px-3"
          >
            <Filter className="size-3.5" />
            {t('Period · Project · User')}
          </Button>
        </div>

        {/* Table */}
        <Card className="gap-0 overflow-hidden py-0">
          {movements.length === 0 ? (
            <div className="flex flex-col items-center justify-center p-16 text-center">
              <Package className="size-10 text-muted-foreground" />
              <h3 className="mt-4 text-lg font-semibold">{t('No movements yet')}</h3>
              <p className="mt-2 text-sm text-muted-foreground">
                {canWrite ? t('Record your first stock movement to start building the ledger.') : t('No stock movements have been recorded yet.')}
              </p>
              {canWrite && (
                <Button className="mt-4" onClick={openNewDialog}>
                  <Plus className="mr-2 size-4" />
                  {t('New Movement')}
                </Button>
              )}
            </div>
          ) : (
            <>
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow className="bg-muted hover:bg-muted">
                      <TableHead className="py-2">{t('Date')}</TableHead>
                      <TableHead className="py-2">{t('Type')}</TableHead>
                      <TableHead className="py-2">{t('Reference')}</TableHead>
                      <TableHead className="py-2">{t('Reason')}</TableHead>
                      <TableHead className="py-2">{t('Location')}</TableHead>
                      <TableHead className="py-2">{t('User')}</TableHead>
                      <TableHead className="py-2 text-right">{t('Quantity')}</TableHead>
                      <TableHead className="py-2 text-right">{t('Stock After')}</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {movements.map((m) => {
                      const { date, time } = formatDateTime(m.created_at)
                      return (
                        <TableRow key={m.id}>
                          <TableCell className="py-2.5 whitespace-nowrap">
                            <div className="font-mono text-sm">{date}</div>
                            <div className="font-mono text-xs text-muted-foreground">{time}</div>
                          </TableCell>
                          <TableCell className="py-2.5">
                            <span className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${TYPE_META[m.movement_type].className}`}>
                              {TYPE_META[m.movement_type].label}
                            </span>
                          </TableCell>
                          <TableCell className="py-2.5">
                            <div className="font-mono text-sm font-semibold">{m.part.reference}</div>
                            {m.part.category && (
                              <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                                <span className="size-1.5 shrink-0 rounded-sm" style={{ backgroundColor: m.part.category.color || 'var(--muted-foreground)' }} />
                                {m.part.category.name}
                              </div>
                            )}
                          </TableCell>
                          <TableCell className="py-2.5 max-w-[240px] truncate text-sm text-muted-foreground">
                            {m.reason || '-'}
                          </TableCell>
                          <TableCell className="py-2.5 font-mono text-sm text-muted-foreground">
                            {m.location_name}
                          </TableCell>
                          <TableCell className="py-2.5 text-sm text-muted-foreground">
                            {m.user_name || '-'}
                          </TableCell>
                          <TableCell className={`py-2.5 text-right font-mono text-sm font-semibold ${
                            m.quantity_delta > 0 ? 'text-emerald-600 dark:text-emerald-400' : m.quantity_delta < 0 ? 'text-red-600 dark:text-red-400' : ''
                          }`}>
                            {m.quantity_delta > 0 ? '+' : ''}{formatQuantity(m.quantity_delta, m.part.unit)}
                          </TableCell>
                          <TableCell className="py-2.5 text-right font-mono text-sm text-muted-foreground">
                            {formatQuantity(m.balance_after, m.part.unit)}
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </div>

              {pagination.page_count > 1 && (
                <div className="flex items-center justify-between border-t px-4 py-2.5 text-sm text-muted-foreground">
                  <span>{tn('{count} movement', '{count} movements', pagination.total)} · {t('Page {page}/{pages}', { page: pagination.page, pages: pagination.page_count })}</span>
                  <div className="flex gap-2">
                    <Button variant="outline" size="sm" disabled={pagination.page <= 1} onClick={() => navigate({ page: pagination.page - 1 })}>
                      <ChevronLeft className="size-4" />
                      {t('Previous')}
                    </Button>
                    <Button variant="outline" size="sm" disabled={pagination.page >= pagination.page_count} onClick={() => navigate({ page: pagination.page + 1 })}>
                      {t('Next')}
                      <ChevronRight className="size-4" />
                    </Button>
                  </div>
                </div>
              )}
            </>
          )}
        </Card>
      </div>

      {/* New movement modal */}
      <Dialog open={newOpen} onOpenChange={setNewOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('New movement')}</DialogTitle>
          </DialogHeader>
          <form onSubmit={submitNew} className="flex flex-col gap-4">
            <Field>
              <FieldLabel>
                <Label>{t('Part')}</Label>
              </FieldLabel>
              <FieldContent>
                <Select
                  value={newForm.data.stock_movement.part_id}
                  onValueChange={(value) => newForm.setData('stock_movement', { ...newForm.data.stock_movement, part_id: value })}
                >
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder={t('Select a part')} />
                  </SelectTrigger>
                  <SelectContent>
                    {parts.map((part) => (
                      <SelectItem key={part.id} value={part.id.toString()}>{part.reference} · {part.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </FieldContent>
              {newForm.errors['stock_movement.part_id'] && <FieldError>{newForm.errors['stock_movement.part_id']}</FieldError>}
            </Field>
            <Field>
              <FieldLabel>
                <Label>{t('Location')}</Label>
              </FieldLabel>
              <FieldContent>
                <StorageLocationSelect
                  locations={storage_locations}
                  value={newForm.data.stock_movement.storage_location_id}
                  onValueChange={(value) => newForm.setData('stock_movement', { ...newForm.data.stock_movement, storage_location_id: value })}
                  placeholder={t('Select a location')}
                  allowCreate
                />
              </FieldContent>
              {newForm.errors['stock_movement.storage_location_id'] && <FieldError>{newForm.errors['stock_movement.storage_location_id']}</FieldError>}
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field>
                <FieldLabel>
                  <Label>{t('Type')}</Label>
                </FieldLabel>
                <FieldContent>
                  <Select
                    value={newForm.data.stock_movement.movement_type}
                    onValueChange={(value) => newForm.setData('stock_movement', { ...newForm.data.stock_movement, movement_type: value as MovementFormData['stock_movement']['movement_type'] })}
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="in">{t('Inbound')}</SelectItem>
                      <SelectItem value="out">{t('Outbound')}</SelectItem>
                      <SelectItem value="adjustment">{t('Adjustment')}</SelectItem>
                    </SelectContent>
                  </Select>
                </FieldContent>
              </Field>
              {newForm.data.stock_movement.movement_type === 'adjustment' ? (
                <Field>
                  <FieldLabel>
                    <Label>{t('Direction')}</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Select
                      value={newForm.data.stock_movement.direction}
                      onValueChange={(value) => newForm.setData('stock_movement', { ...newForm.data.stock_movement, direction: value as MovementFormData['stock_movement']['direction'] })}
                    >
                      <SelectTrigger className="w-full">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="increase">{t('Increase')}</SelectItem>
                        <SelectItem value="decrease">{t('Decrease')}</SelectItem>
                      </SelectContent>
                    </Select>
                  </FieldContent>
                </Field>
              ) : (
                <Field>
                  <FieldLabel>
                    <Label>{t('Quantity')}</Label>
                  </FieldLabel>
                  <FieldContent>
                    <QuantityInput
                      unit={selectedPart?.unit}
                      packSize={selectedPart?.pack_size}
                      value={newForm.data.stock_movement.quantity}
                      onValueChange={(quantity) => newForm.setData('stock_movement', { ...newForm.data.stock_movement, quantity })}
                    />
                  </FieldContent>
                </Field>
              )}
            </div>
            {newForm.data.stock_movement.movement_type === 'adjustment' && (
              <Field>
                <FieldLabel>
                  <Label>{t('Quantity')}</Label>
                </FieldLabel>
                <FieldContent>
                  <QuantityInput
                    unit={selectedPart?.unit}
                    packSize={selectedPart?.pack_size}
                    value={newForm.data.stock_movement.quantity}
                    onValueChange={(quantity) => newForm.setData('stock_movement', { ...newForm.data.stock_movement, quantity })}
                  />
                </FieldContent>
              </Field>
            )}
            {(newForm.errors as Record<string, string>)['stock_movement.quantity_delta'] && (
              <FieldError>{(newForm.errors as Record<string, string>)['stock_movement.quantity_delta']}</FieldError>
            )}
            <Field>
              <FieldLabel>
                <Label>{t('Reason')} <span className="font-normal text-muted-foreground">{t('(optional)')}</span></Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  placeholder={t('e.g. Project «  Sensor board v3 »')}
                  value={newForm.data.stock_movement.reason}
                  onChange={(e) => newForm.setData('stock_movement', { ...newForm.data.stock_movement, reason: e.target.value })}
                />
              </FieldContent>
            </Field>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setNewOpen(false)}>{t('Cancel')}</Button>
              <Button type="submit" disabled={newForm.processing}>{t('Record movement')}</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </AppLayout>
  )
}
