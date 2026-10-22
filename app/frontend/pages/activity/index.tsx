import { Head, Link, router } from '@inertiajs/react'
import { useState } from 'react'
import { ArrowRight, ChevronLeft, ChevronRight, History, X } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { PartDetailSheet } from '@/components/part-detail-sheet'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
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
import { t, intlLocale, tn } from '@/lib/i18n'

type DetailValue = string | number | boolean | null | string[]

interface ActivityEvent {
  id: number
  created_at: string
  action: string
  user_name: string | null
  subject_type: string | null
  subject_id: number | null
  subject_label: string | null
  subject_exists: boolean
  subject_url: string | null
  // Updates: { attribute: [before, after] } (null: a secret that changed).
  // Summary events (import, merge…): { fact: value }.
  details: Record<string, DetailValue | [DetailValue, DetailValue]>
}

interface Filters {
  user_id: string | null
  subject_type: string | null
  event_action: string | null
  subject_id: number | null
  subject_label: string | null
}

interface ActivityPageProps {
  events: ActivityEvent[]
  pagination: { page: number; page_count: number; total: number; page_size: number }
  filters: Filters
  users: { id: number; name: string }[]
  subject_types: string[]
}

const ACTION_META: Record<string, { label: string; className: string }> = {
  create: { get label() { return t('Created') }, className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
  update: { get label() { return t('Updated') }, className: 'bg-sky-100 text-sky-700 dark:bg-sky-950 dark:text-sky-400' },
  destroy: { get label() { return t('Deleted') }, className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
  import: { get label() { return t('Imported') }, className: 'bg-violet-100 text-violet-700 dark:bg-violet-950 dark:text-violet-400' },
  merge: { get label() { return t('Merged') }, className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
  reset: { get label() { return t('Data reset') }, className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
  export: { get label() { return t('Exported') }, className: 'bg-muted text-muted-foreground' },
  restore: { get label() { return t('Restored') }, className: 'bg-violet-100 text-violet-700 dark:bg-violet-950 dark:text-violet-400' },
}

const SUBJECT_TYPES: Record<string, string> = {
  get Part() { return t('Part') },
  get Category() { return t('Category') },
  get Footprint() { return t('Footprint') },
  get Tag() { return t('Tag') },
  get ParameterDefinition() { return t('Parameter') },
  get StorageLocation() { return t('Storage zone') },
  get Supplier() { return t('Supplier') },
  get Order() { return t('Purchase order') },
  get Project() { return t('Project') },
  get Stocktake() { return t('Stocktake') },
  get Loan() { return t('Loan') },
  get LabelPrinter() { return t('Label printer') },
  get OrganizationMembership() { return t('Member') },
  get Organization() { return t('Organization') },
}

// Labels for the attributes and facts events carry; anything else is shown
// humanized ("lead_time_days" → "Lead time days").
const FIELD_LABELS: Record<string, string> = {
  get name() { return t('Name') },
  get description() { return t('Description') },
  get notes() { return t('Notes') },
  get code() { return t('Code') },
  get color() { return t('Color') },
  get status() { return t('Status') },
  get category() { return t('Category') },
  get footprint() { return t('Footprint') },
  get parent() { return t('Parent') },
  get supplier() { return t('Supplier') },
  get storage_location() { return t('Storage zone') },
  get bag() { return t('Bag') },
  get mpn() { return t('MPN') },
  get sku() { return t('SKU') },
  get barcode() { return t('Barcode') },
  get ipn() { return t('IPN') },
  get manufacturer() { return t('Manufacturer') },
  get value() { return t('Value') },
  get unit() { return t('Unit') },
  get unit_price() { return t('Unit price') },
  get min_stock_threshold() { return t('Min. threshold') },
  get target_stock() { return t('Target stock') },
  get location_type() { return t('Type') },
  get email() { return t('Email') },
  get phone() { return t('Phone') },
  get website() { return t('Website') },
  get reference() { return t('Reference') },
  get expected_delivery() { return t('Expected delivery') },
  get revision() { return t('Revision') },
  get due_on() { return t('Due date') },
  get borrower_name() { return t('Borrower') },
  get closed_at() { return t('Closed') },
  get role() { return t('Role') },
  get active() { return t('Active') },
  get host() { return t('Host') },
  get port() { return t('Port') },
  get timezone() { return t('Timezone') },
  get address_line1() { return t('Address line 1') },
  get address_line2() { return t('Address line 2') },
  get city() { return t('City') },
  get postcode() { return t('Postcode') },
  get country() { return t('Country') },
  get lead_time_days() { return t('Lead time') },
  get default_low_stock_threshold() { return t('Default low-stock threshold') },
  get default_loan_days() { return t('Default loan duration (days)') },
  get allow_negative_stock() { return t('Allow negative stock') },
  get stock_reservations_enabled() { return t('Stock reservations') },
  get lcsc_enabled() { return t('LCSC lookup') },
  get notification_frequency() { return t('Email frequency') },
  get notify_low_stock() { return t('Low stock emails') },
  get notify_late_orders() { return t('Late order emails') },
  get notify_overdue_loans() { return t('Overdue loan emails') },
  get ipn_prefix() { return t('IPN prefix') },
  get ipn_separator() { return t('IPN separator') },
  get ipn_digits() { return t('IPN digits') },
  get ipn_generation_mode() { return t('IPN generation mode') },
  get currency() { return t('Currency') },
  get mouser_api_key() { return t('Mouser API key') },
  get mouser_order_api_key() { return t('Mouser Order API key') },
  get digikey_client_id() { return t('DigiKey client ID') },
  get digikey_client_secret() { return t('DigiKey client secret') },
  get kicad_token_digest() { return t('KiCad token') },
  get github_token() { return t('GitHub token') },
  get merged() { return t('Merged parts') },
  get parts() { return t('Parts') },
  get records() { return t('Records') },
  get file() { return t('File') },
  get created() { return t('New parts') },
  get updated() { return t('Updated parts') },
  get skipped() { return t('Skipped rows') },
  get organization() { return t('Organization') },
  get parts_moved() { return t('Parts moved') },
  get parts_merged() { return t('Parts merged') },
  get ipns_reassigned() { return t('IPNs reassigned') },
}

// Enumerated values (roles, statuses, digest frequency) shown translated.
const VALUE_LABELS: Record<string, string> = {
  get owner() { return t('Owner') },
  get admin() { return t('Admin') },
  get member() { return t('Member') },
  get viewer() { return t('Viewer') },
  get daily() { return t('Daily') },
  get weekly() { return t('Weekly') },
  get pending() { return t('Pending') },
  get shipped() { return t('Shipped') },
  get received() { return t('Received') },
  get cancelled() { return t('Cancelled') },
  get draft() { return t('Draft') },
  get confirmed() { return t('Confirmed') },
  get active() { return t('Active') },
  get discontinued() { return t('Discontinued') },
  get obsolete() { return t('Obsolete') },
  get in_progress() { return t('In progress') },
  get completed() { return t('Completed') },
}
const ENUM_FIELDS = new Set(['role', 'status', 'notification_frequency'])

function fieldLabel(key: string) {
  if (key in FIELD_LABELS) return FIELD_LABELS[key]
  const words = key.replace(/_/g, ' ')
  return words.charAt(0).toUpperCase() + words.slice(1)
}

function formatValue(value: DetailValue, key?: string) {
  if (value === null || value === '') return '—'
  if (typeof value === 'boolean') return value ? t('Yes') : t('No')
  if (typeof value === 'number') return value.toLocaleString(intlLocale())
  if (Array.isArray(value)) return value.join(', ')
  if (key && ENUM_FIELDS.has(key) && value in VALUE_LABELS) return VALUE_LABELS[value]
  return value
}

// Creates and updates carry [before, after] pairs; summary events plain facts.
function isChange(event: ActivityEvent, value: unknown): value is [DetailValue, DetailValue] {
  return (event.action === 'create' || event.action === 'update') && Array.isArray(value) && value.length === 2
}

function EventDetails({ event }: { event: ActivityEvent }) {
  const entries = Object.entries(event.details)
  if (entries.length === 0) return <span className="text-muted-foreground">—</span>

  return (
    <ul className="space-y-0.5">
      {entries.map(([key, value]) => (
        <li key={key} className="flex flex-wrap items-center gap-x-1.5 text-xs">
          <span className="text-muted-foreground">{fieldLabel(key)}</span>
          {value === null ? (
            <span className="italic">{t('changed')}</span>
          ) : isChange(event, value) ? (
            <>
              {event.action !== 'create' && (
                <>
                  <span className="max-w-[200px] truncate line-through decoration-muted-foreground/60">{formatValue(value[0], key)}</span>
                  <ArrowRight className="size-3 text-muted-foreground" />
                </>
              )}
              <span className="max-w-[200px] truncate font-medium">{formatValue(value[1], key)}</span>
            </>
          ) : (
            <span className="font-medium">{formatValue(value as DetailValue)}</span>
          )}
        </li>
      ))}
    </ul>
  )
}

const ALL = 'all'

export default function ActivityIndex({ events, pagination, filters, users, subject_types }: ActivityPageProps) {
  const [detailPartId, setDetailPartId] = useState<number | null>(null)

  // Filters and pages are server-side: navigate with the new query.
  const navigate = (next: Partial<Filters> & { page?: number }) => {
    const merged = { ...filters, ...next }
    const query: Record<string, string | number> = {}
    if (merged.user_id) query.user_id = merged.user_id
    if (merged.subject_type) query.subject_type = merged.subject_type
    if (merged.subject_type && merged.subject_id) query.subject_id = merged.subject_id
    if (merged.event_action) query.event_action = merged.event_action
    if (next.page && next.page > 1) query.page = next.page
    router.get('/activity', query, { preserveScroll: true, preserveState: true })
  }

  const filtered = Boolean(filters.user_id || filters.subject_type || filters.event_action)

  const subjectCell = (event: ActivityEvent) => {
    if (!event.subject_type) return <span className="text-muted-foreground">{t('Organization')}</span>

    const label = event.subject_label || `#${event.subject_id}`
    let name
    if (event.subject_type === 'Part' && event.subject_exists && event.subject_id) {
      const partId = event.subject_id
      name = (
        <Button variant="link" className="h-auto p-0 text-sm font-medium" onClick={() => setDetailPartId(partId)}>
          {label}
        </Button>
      )
    } else if (event.subject_url) {
      name = <Link href={event.subject_url} className="font-medium hover:underline">{label}</Link>
    } else {
      name = <span className={event.subject_exists ? 'font-medium' : 'font-medium text-muted-foreground'}>{label}</span>
    }

    return (
      <div>
        <div className="text-xs text-muted-foreground">{SUBJECT_TYPES[event.subject_type] ?? event.subject_type}</div>
        <div className="flex items-center gap-1.5">
          {name}
          {event.subject_id && !(filters.subject_type === event.subject_type && filters.subject_id === event.subject_id) && (
            <Button
              variant="ghost"
              size="icon-sm"
              className="size-6 text-muted-foreground"
              title={t('History of this record')}
              onClick={() => navigate({ subject_type: event.subject_type, subject_id: event.subject_id, user_id: null, event_action: null, page: 1 })}
            >
              <History className="size-3.5" />
            </Button>
          )}
        </div>
      </div>
    )
  }

  return (
    <AppLayout header={<PageHeader title={t('Activity')} subtitle={t('Who changed what in the organization')} />}>
      <Head title={t('Activity')} />

      <div className="space-y-6">
        <FlashMessages />

        <div className="flex flex-wrap items-center gap-2">
          <Select value={filters.user_id ?? ALL} onValueChange={(value) => navigate({ user_id: value === ALL ? null : value, page: 1 })}>
            <SelectTrigger size="sm" className="w-48">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>{t('All members')}</SelectItem>
              {users.map((user) => (
                <SelectItem key={user.id} value={user.id.toString()}>{user.name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select
            value={filters.subject_type ?? ALL}
            onValueChange={(value) => navigate({ subject_type: value === ALL ? null : value, subject_id: null, page: 1 })}
          >
            <SelectTrigger size="sm" className="w-48">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>{t('All records')}</SelectItem>
              {subject_types.map((type) => (
                <SelectItem key={type} value={type}>{SUBJECT_TYPES[type] ?? type}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={filters.event_action ?? ALL} onValueChange={(value) => navigate({ event_action: value === ALL ? null : value, page: 1 })}>
            <SelectTrigger size="sm" className="w-44">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>{t('All actions')}</SelectItem>
              {Object.entries(ACTION_META).map(([action, meta]) => (
                <SelectItem key={action} value={action}>{meta.label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          {filters.subject_type && filters.subject_id && (
            <span className="text-sm text-muted-foreground">
              {t('History of {record}', { record: filters.subject_label || `#${filters.subject_id}` })}
            </span>
          )}
          {filtered && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => navigate({ user_id: null, subject_type: null, subject_id: null, event_action: null, page: 1 })}
            >
              <X className="size-4" />
              {t('Clear filters')}
            </Button>
          )}
        </div>

        <Card className="gap-0 overflow-hidden py-0">
          {events.length === 0 ? (
            <div className="flex flex-col items-center justify-center p-16 text-center">
              <History className="size-10 text-muted-foreground" />
              <h3 className="mt-4 text-lg font-semibold">{filtered ? t('No matching activity') : t('No activity yet')}</h3>
              <p className="mt-2 max-w-md text-sm text-muted-foreground">
                {t('Parts, zones, orders, projects, members and settings created, changed or deleted by members show up here.')}
              </p>
            </div>
          ) : (
            <>
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow className="bg-muted hover:bg-muted">
                      <TableHead className="py-2">{t('Date')}</TableHead>
                      <TableHead className="py-2">{t('Member')}</TableHead>
                      <TableHead className="py-2">{t('Action')}</TableHead>
                      <TableHead className="py-2">{t('Record')}</TableHead>
                      <TableHead className="py-2">{t('Details')}</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {events.map((event) => {
                      const date = new Date(event.created_at)
                      const meta = ACTION_META[event.action]
                      return (
                        <TableRow key={event.id} className="align-top">
                          <TableCell className="py-2.5 whitespace-nowrap">
                            <div className="font-mono text-sm">{date.toLocaleDateString(intlLocale(), { day: '2-digit', month: '2-digit', year: 'numeric' })}</div>
                            <div className="font-mono text-xs text-muted-foreground">{date.toLocaleTimeString(intlLocale(), { hour: '2-digit', minute: '2-digit' })}</div>
                          </TableCell>
                          <TableCell className="py-2.5 text-sm">{event.user_name || '—'}</TableCell>
                          <TableCell className="py-2.5">
                            <span className={`rounded-full px-2.5 py-0.5 text-xs font-semibold whitespace-nowrap ${meta?.className ?? 'bg-muted text-muted-foreground'}`}>
                              {meta?.label ?? event.action}
                            </span>
                          </TableCell>
                          <TableCell className="py-2.5 text-sm">{subjectCell(event)}</TableCell>
                          <TableCell className="py-2.5 min-w-[240px]"><EventDetails event={event} /></TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </div>

              {pagination.page_count > 1 && (
                <div className="flex items-center justify-between border-t px-4 py-2.5 text-sm text-muted-foreground">
                  <span>{tn('{count} event', '{count} events', pagination.total)} · {t('Page {page}/{pages}', { page: pagination.page, pages: pagination.page_count })}</span>
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

      <PartDetailSheet
        partId={detailPartId}
        open={detailPartId !== null}
        onOpenChange={(open) => !open && setDetailPartId(null)}
      />
    </AppLayout>
  )
}
