import { Head, Link, usePage } from '@inertiajs/react'
import { useState, type ReactNode } from 'react'
import {
  AlertTriangle,
  ArrowRight,
  CheckCircle2,
  Circle,
  CircleCheck,
  Clock,
  Coins,
  FolderKanban,
  PackageX,
  Package,
  Plus,
  ScanLine,
  Truck,
  type LucideIcon,
} from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { GlobalSearch } from '@/components/global-search'
import { PartDetailSheet } from '@/components/part-detail-sheet'
import { ActivityChart, type ActivityDay } from '@/components/dashboard/activity-chart'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { t, tn, intlLocale } from '@/lib/i18n'

interface Stats {
  references_count: number
  new_references_count: number
  total_units: number
  stock_value: number
  alerts_count: number
  out_of_stock_count: number
  open_orders_count: number
  late_orders_count: number
  incoming_value: number
  projects_count: number
  currency: string
}

interface AttentionItem {
  kind: 'late_orders' | 'shipped_orders' | 'out_of_stock' | 'low_stock' | 'projects_short'
  count: number
  href: string
}

interface CategoryBreakdownEntry {
  name: string
  count: number
  pct: number
}

interface LowStockPart {
  id: number
  reference: string
  name: string
  location_name: string | null
  quantity: number
  min_stock_threshold: number
  incoming: number
}

interface OpenOrder {
  id: number
  reference: string | null
  supplier_name: string
  status: 'pending' | 'shipped'
  expected_delivery: string | null
  days_late: number
  lines_count: number
  total_amount: number
}

interface ProjectSummary {
  id: number
  name: string
  reference: string | null
  status: 'draft' | 'confirmed'
  reserved: boolean
  lines_count: number
  buildable: boolean
  short_count: number
  builds_count: number
  last_built_at: string | null
}

interface ConsumedPart {
  id: number
  reference: string
  name: string
  units: number
}

interface RecentMovement {
  id: number
  part_id: number
  reference: string
  part_name: string
  location_name: string
  movement_type: 'in' | 'out' | 'adjustment'
  quantity_delta: number
  reason: string | null
  user_name: string | null
  created_at: string
}

interface GettingStarted {
  zone: boolean
  supplier: boolean
  part: boolean
  movement: boolean
}

interface DashboardProps {
  [key: string]: unknown
  stats: Stats
  activity: ActivityDay[]
  attention: AttentionItem[]
  category_breakdown: CategoryBreakdownEntry[]
  low_stock_parts: LowStockPart[]
  open_orders: OpenOrder[]
  projects: ProjectSummary[]
  top_consumed: ConsumedPart[]
  recent_movements: RecentMovement[]
  getting_started: GettingStarted | null
  auth?: { user?: { firstname?: string | null } }
}

const CURRENCY_SYMBOLS: Record<string, string> = {
  EUR: '€',
  USD: '$',
  GBP: '£',
  CHF: 'CHF',
}

function formatMoney(value: number, currency: string) {
  const symbol = CURRENCY_SYMBOLS[currency] || currency
  return `${Math.round(value).toLocaleString(intlLocale())} ${symbol}`
}

const MOVEMENT_META: Record<RecentMovement['movement_type'], { label: string; className: string }> = {
  in: { get label() { return t('In') }, className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400' },
  out: { get label() { return t('Out') }, className: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400' },
  adjustment: { get label() { return t('Adjustment') }, className: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400' },
}

const ATTENTION_META: Record<AttentionItem['kind'], { icon: LucideIcon; label: (count: number) => string; tone: string }> = {
  late_orders: {
    icon: Clock,
    label: (n) => tn('{count} order is past expected delivery', '{count} orders are past expected delivery', n),
    tone: 'text-destructive',
  },
  out_of_stock: {
    icon: PackageX,
    label: (n) => tn('{count} part is out of stock', '{count} parts are out of stock', n),
    tone: 'text-destructive',
  },
  low_stock: {
    icon: AlertTriangle,
    label: (n) => tn('{count} part is running low', '{count} parts are running low', n),
    tone: 'text-amber-600 dark:text-amber-500',
  },
  projects_short: {
    icon: FolderKanban,
    label: (n) => tn('{count} confirmed project is short of parts', '{count} confirmed projects are short of parts', n),
    tone: 'text-amber-600 dark:text-amber-500',
  },
  shipped_orders: {
    icon: Truck,
    label: (n) => tn('{count} shipped order to receive', '{count} shipped orders to receive', n),
    tone: 'text-sky-600 dark:text-sky-400',
  },
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(intlLocale(), { day: 'numeric', month: 'short' })
}

// Plain dates (no time) from the server, read as local noon so they never
// shift a day.
function formatDay(iso: string) {
  return formatDate(`${iso}T12:00:00`)
}

const RELATIVE = new Intl.RelativeTimeFormat(intlLocale(), { numeric: 'auto' })

function timeAgo(iso: string) {
  const seconds = Math.round((new Date(iso).getTime() - Date.now()) / 1000)
  const steps: [Intl.RelativeTimeFormatUnit, number][] = [
    ['day', 86400],
    ['hour', 3600],
    ['minute', 60],
  ]
  for (const [unit, size] of steps) {
    if (Math.abs(seconds) >= size) {
      if (unit === 'day' && Math.abs(seconds) >= 7 * 86400) return formatDate(iso)
      return RELATIVE.format(Math.round(seconds / size), unit)
    }
  }
  return t('just now')
}

function greeting() {
  const hour = new Date().getHours()
  if (hour < 5 || hour >= 18) return t('Good evening')
  if (hour < 12) return t('Good morning')
  return t('Good afternoon')
}

function SectionHeader({ title, description, href }: { title: string; description?: string; href?: string }) {
  return (
    <CardHeader className="flex flex-row items-center justify-between gap-2 border-b py-4">
      <div className="min-w-0">
        <CardTitle>{title}</CardTitle>
        {description && <CardDescription className="text-xs">{description}</CardDescription>}
      </div>
      {href && (
        <Link href={href} className="shrink-0 text-sm font-medium text-muted-foreground hover:text-foreground">
          {t('See all →')}
        </Link>
      )}
    </CardHeader>
  )
}

function StatCard({
  label,
  value,
  detail,
  icon: Icon,
  href,
  tone,
}: {
  label: string
  value: string
  detail: ReactNode
  icon: LucideIcon
  href: string
  tone?: 'alert' | 'warning'
}) {
  const toneClass = tone === 'alert' ? 'text-destructive' : tone === 'warning' ? 'text-amber-600 dark:text-amber-500' : ''
  return (
    <Link href={href} className="group rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
      <Card className="h-full gap-2 transition-colors group-hover:border-foreground/20">
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-0">
          <CardTitle className="text-sm font-medium text-muted-foreground">{label}</CardTitle>
          <Icon className={`size-4 ${toneClass || 'text-muted-foreground'}`} />
        </CardHeader>
        <CardContent className="space-y-1">
          <div className={`text-2xl font-bold tabular-nums ${toneClass}`}>{value}</div>
          <p className="text-xs text-muted-foreground">{detail}</p>
        </CardContent>
      </Card>
    </Link>
  )
}

function GettingStartedCard({ steps, canWrite }: { steps: GettingStarted; canWrite: boolean }) {
  const items = [
    { done: steps.zone, label: t('Create your storage zones'), hint: t('Rooms, cabinets, drawers and boxes.'), href: '/storage_locations' },
    { done: steps.supplier, label: t('Add your suppliers'), hint: t('Or connect Mouser and DigiKey in Settings.'), href: '/suppliers' },
    { done: steps.part, label: t('Add your first part'), hint: t('By hand, from a supplier lookup or a CSV import.'), href: '/parts?new=1' },
    { done: steps.movement, label: t('Put stock on a shelf'), hint: t('Record a stock entry or receive an order.'), href: '/parts' },
  ]
  const doneCount = items.filter((item) => item.done).length

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t('Get started')}</CardTitle>
        <CardDescription>
          {t('{done} of {total} done. A few steps and this page fills up with your stock.', { done: doneCount, total: items.length })}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ol className="grid gap-2 sm:grid-cols-2">
          {items.map((item) => {
            const content = (
              <>
                {item.done ? (
                  <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-emerald-600" />
                ) : (
                  <Circle className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
                )}
                <div>
                  <p className={`text-sm font-medium ${item.done ? 'text-muted-foreground line-through' : ''}`}>{item.label}</p>
                  <p className="text-xs text-muted-foreground">{item.hint}</p>
                </div>
              </>
            )
            return (
              <li key={item.label}>
                {canWrite && !item.done ? (
                  <Link href={item.href} className="flex gap-3 rounded-lg border p-3 hover:bg-muted/50">
                    {content}
                  </Link>
                ) : (
                  <div className="flex gap-3 rounded-lg border p-3">{content}</div>
                )}
              </li>
            )
          })}
        </ol>
      </CardContent>
    </Card>
  )
}

export default function Dashboard({
  stats,
  activity,
  attention,
  category_breakdown,
  low_stock_parts,
  open_orders,
  projects,
  top_consumed,
  recent_movements,
  getting_started,
}: DashboardProps) {
  const { canWrite } = usePermissions()
  const { auth } = usePage<DashboardProps>().props
  const [detailPartId, setDetailPartId] = useState<number | null>(null)

  const firstname = auth?.user?.firstname
  const activityTotals = activity.reduce(
    (sum, day) => ({ in: sum.in + day.in, out: sum.out + day.out, adjustment: sum.adjustment + day.adjustment }),
    { in: 0, out: 0, adjustment: 0 },
  )
  const movementsCount = activityTotals.in + activityTotals.out + activityTotals.adjustment
  const maxConsumed = Math.max(1, ...top_consumed.map((part) => part.units))

  const partLink = (id: number, reference: string) => (
    <Button
      type="button"
      variant="link"
      onClick={() => setDetailPartId(id)}
      className="h-auto max-w-full justify-start truncate p-0 text-left font-mono font-semibold text-foreground"
    >
      {reference}
    </Button>
  )

  return (
    <AppLayout
      header={
        <PageHeader
          title={t('Dashboard')}
          subtitle={firstname
            ? t('{greeting}, {name}. Here\'s what\'s happening in your inventory.', { greeting: greeting(), name: firstname })
            : t('{greeting}. Here\'s what\'s happening in your inventory.', { greeting: greeting() })}
        >
          <GlobalSearch />
          <Button size="sm" variant="outline" asChild>
            <Link href="/scan">
              <ScanLine className="size-4" />
              {t('Scan')}
            </Link>
          </Button>
          {canWrite && (
            <Button size="sm" asChild>
              <Link href="/parts?new=1">
                <Plus className="size-4" />
                {t('New component')}
              </Link>
            </Button>
          )}
        </PageHeader>
      }
    >
      <Head title={t('Dashboard')} />

      <div className="space-y-6">
        {getting_started && <GettingStartedCard steps={getting_started} canWrite={canWrite} />}

        {/* Headline figures */}
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <StatCard
            label={t('References')}
            value={stats.references_count.toLocaleString(intlLocale())}
            detail={
              stats.new_references_count > 0
                ? t('+{count} in the last 30 days', { count: stats.new_references_count.toLocaleString(intlLocale()) })
                : tn('{count} unit in stock', '{count} units in stock', stats.total_units, { count: stats.total_units.toLocaleString(intlLocale()) })
            }
            icon={Package}
            href="/parts"
          />
          <StatCard
            label={t('Stock value')}
            value={formatMoney(stats.stock_value, stats.currency)}
            detail={tn('{count} unit in stock', '{count} units in stock', stats.total_units, { count: stats.total_units.toLocaleString(intlLocale()) })}
            icon={Coins}
            href="/parts"
          />
          <StatCard
            label={t('Low stock')}
            value={stats.alerts_count.toLocaleString(intlLocale())}
            detail={stats.out_of_stock_count > 0 ? t('{count} out of stock', { count: stats.out_of_stock_count.toLocaleString(intlLocale()) }) : t('Nothing out of stock')}
            icon={AlertTriangle}
            href="/alerts"
            tone={stats.out_of_stock_count > 0 ? 'alert' : stats.alerts_count > 0 ? 'warning' : undefined}
          />
          <StatCard
            label={t('Open orders')}
            value={stats.open_orders_count.toLocaleString(intlLocale())}
            detail={
              stats.late_orders_count > 0
                ? t('{count} late', { count: stats.late_orders_count.toLocaleString(intlLocale()) })
                : stats.open_orders_count > 0
                  ? t('{amount} incoming', { amount: formatMoney(stats.incoming_value, stats.currency) })
                  : t('Nothing on its way')
            }
            icon={Truck}
            href="/orders"
            tone={stats.late_orders_count > 0 ? 'alert' : undefined}
          />
        </div>

        {/* Activity + to-do */}
        <div className="grid gap-4 lg:grid-cols-[1.6fr_1fr]">
          <Card className="gap-0 py-0">
            <SectionHeader
              title={t('Stock activity')}
              description={
                movementsCount > 0
                  ? tn('{count} movement in the last 30 days: {in} in, {out} out, {adjustments} adjustments', '{count} movements in the last 30 days: {in} in, {out} out, {adjustments} adjustments', movementsCount, { count: movementsCount.toLocaleString(intlLocale()), in: activityTotals.in, out: activityTotals.out, adjustments: activityTotals.adjustment })
                  : t('No movements in the last 30 days')
              }
              href="/stock_movements"
            />
            <CardContent className="pt-5 pb-4">
              <ActivityChart days={activity} />
            </CardContent>
          </Card>

          <Card className="gap-0 py-0">
            <SectionHeader title={t('Needs attention')} />
            <CardContent className="p-0">
              {attention.length > 0 ? (
                <ul className="divide-y">
                  {attention.map((item) => {
                    const meta = ATTENTION_META[item.kind]
                    return (
                      <li key={item.kind}>
                        <Link href={item.href} className="flex items-center gap-3 px-6 py-3 text-sm hover:bg-muted/50">
                          <meta.icon className={`size-4 shrink-0 ${meta.tone}`} />
                          <span className="flex-1">{meta.label(item.count)}</span>
                          <ArrowRight className="size-4 text-muted-foreground" />
                        </Link>
                      </li>
                    )
                  })}
                </ul>
              ) : (
                <div className="flex flex-col items-center gap-2 px-6 py-10 text-center">
                  <CircleCheck className="size-8 text-emerald-600" />
                  <p className="text-sm font-medium">{t('All good')}</p>
                  <p className="text-xs text-muted-foreground">{t('No low stock, late orders or blocked projects.')}</p>
                </div>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Low stock + orders */}
        <div className="grid gap-4 lg:grid-cols-[1.6fr_1fr]">
          <Card className="gap-0 py-0">
            <SectionHeader title={t('Low stock')} description={t('Under their minimum threshold, most critical first')} href="/alerts" />
            <CardContent className="p-0">
              {low_stock_parts.length > 0 ? (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>{t('Reference')}</TableHead>
                      <TableHead className="hidden sm:table-cell">{t('Location')}</TableHead>
                      <TableHead className="w-[38%]">{t('Stock')}</TableHead>
                      <TableHead className="text-right">{t('On order')}</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {low_stock_parts.map((part) => {
                      const pct = Math.min(100, (part.quantity / part.min_stock_threshold) * 100)
                      return (
                        <TableRow key={part.id}>
                          <TableCell className="max-w-[200px]">
                            {partLink(part.id, part.reference)}
                            <div className="truncate text-xs text-muted-foreground">{part.name}</div>
                          </TableCell>
                          <TableCell className="hidden font-mono text-sm text-muted-foreground sm:table-cell">
                            {part.location_name || '-'}
                          </TableCell>
                          <TableCell>
                            <div className="flex items-baseline justify-between gap-2 font-mono text-xs">
                              <span className={`font-semibold ${part.quantity === 0 ? 'text-destructive' : 'text-amber-600 dark:text-amber-500'}`}>
                                {part.quantity}
                              </span>
                              <span className="text-muted-foreground">/ {part.min_stock_threshold}</span>
                            </div>
                            <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-muted">
                              <div
                                className={`h-full rounded-full ${part.quantity === 0 ? 'bg-destructive' : 'bg-amber-500'}`}
                                style={{ width: `${pct}%` }}
                              />
                            </div>
                          </TableCell>
                          <TableCell className="text-right font-mono text-sm">
                            {part.incoming > 0 ? (
                              <span className="text-sky-600 dark:text-sky-400">+{part.incoming}</span>
                            ) : (
                              <span className="text-muted-foreground">-</span>
                            )}
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              ) : (
                <p className="p-6 text-sm text-muted-foreground">{t('Nothing below threshold.')}</p>
              )}
            </CardContent>
          </Card>

          <Card className="gap-0 py-0">
            <SectionHeader title={t('Orders on their way')} href="/orders" />
            <CardContent className="p-0">
              {open_orders.length > 0 ? (
                <ul className="divide-y">
                  {open_orders.map((order) => (
                    <li key={order.id}>
                      <Link href={`/orders/${order.id}`} className="flex items-center gap-3 px-6 py-3 hover:bg-muted/50">
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-sm font-medium">{order.supplier_name}</p>
                          <p className="truncate font-mono text-xs text-muted-foreground">
                            {order.reference || `#${order.id}`} · {tn('{count} line', '{count} lines', order.lines_count)}
                            {order.total_amount > 0 && ` · ${formatMoney(order.total_amount, stats.currency)}`}
                          </p>
                        </div>
                        <div className="shrink-0 text-right">
                          <Badge variant={order.status === 'shipped' ? 'secondary' : 'outline'}>
                            {order.status === 'shipped' ? t('Shipped') : t('Pending')}
                          </Badge>
                          <p className={`mt-1 text-xs ${order.days_late > 0 ? 'font-medium text-destructive' : 'text-muted-foreground'}`}>
                            {order.days_late > 0
                              ? tn('{count} day late', '{count} days late', order.days_late)
                              : order.expected_delivery
                                ? t('Due {date}', { date: formatDay(order.expected_delivery) })
                                : t('No date')}
                          </p>
                        </div>
                      </Link>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="p-6 text-sm text-muted-foreground">{t('No open orders.')}</p>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Projects, consumption, categories */}
        <div className="grid gap-4 lg:grid-cols-3">
          <Card className="gap-0 py-0">
            <SectionHeader title={t('Projects')} description={t('Can they be built from stock now?')} href="/projects" />
            <CardContent className="p-0">
              {projects.length > 0 ? (
                <ul className="divide-y">
                  {projects.map((project) => (
                    <li key={project.id}>
                      <Link href={`/projects/${project.id}`} className="flex items-center gap-3 px-6 py-3 hover:bg-muted/50">
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-sm font-medium">{project.name}</p>
                          <p className="truncate text-xs text-muted-foreground">
                            {project.status === 'draft' ? t('Draft') : project.reserved ? t('Confirmed, stock reserved') : t('Confirmed')}
                            {project.builds_count > 0 && ` · ${project.last_built_at
                              ? t('built {count}×, last {ago}', { count: project.builds_count, ago: timeAgo(project.last_built_at) })
                              : t('built {count}×', { count: project.builds_count })}`}
                          </p>
                        </div>
                        {project.lines_count === 0 ? (
                          <Badge variant="outline">{t('Empty')}</Badge>
                        ) : project.buildable ? (
                          <Badge className="bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400" variant="outline">
                            {t('Buildable')}
                          </Badge>
                        ) : (
                          <Badge className="bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400" variant="outline">
                            {t('{count} short', { count: project.short_count })}
                          </Badge>
                        )}
                      </Link>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="p-6 text-sm text-muted-foreground">{t('No projects yet. Import a BOM to check what you can build.')}</p>
              )}
            </CardContent>
          </Card>

          <Card className="gap-0 py-0">
            <SectionHeader title={t('Most used')} description={t('Units taken out in the last 30 days')} />
            <CardContent className="space-y-3 py-4">
              {top_consumed.length > 0 ? (
                top_consumed.map((part) => (
                  <div key={part.id} className="space-y-1">
                    <div className="flex items-center justify-between gap-2 text-sm">
                      <div className="min-w-0">{partLink(part.id, part.reference)}</div>
                      <span className="shrink-0 font-mono text-muted-foreground">{part.units.toLocaleString(intlLocale())}</span>
                    </div>
                    <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
                      <div className="h-full rounded-full bg-primary" style={{ width: `${(part.units / maxConsumed) * 100}%` }} />
                    </div>
                  </div>
                ))
              ) : (
                <p className="text-sm text-muted-foreground">{t('Nothing taken out of stock lately.')}</p>
              )}
            </CardContent>
          </Card>

          <Card className="gap-0 py-0">
            <SectionHeader title={t('By category')} description={t('Share of your references')} href="/categories" />
            <CardContent className="space-y-3 py-4">
              {category_breakdown.length > 0 ? (
                category_breakdown.map((entry) => (
                  <div key={entry.name} className="space-y-1">
                    <div className="flex items-center justify-between gap-2 text-sm">
                      <span className="truncate font-medium">{entry.name}</span>
                      <span className="shrink-0 font-mono text-muted-foreground">
                        {entry.count} <span className="text-xs">({entry.pct}%)</span>
                      </span>
                    </div>
                    <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
                      <div className="h-full rounded-full bg-primary" style={{ width: `${entry.pct}%` }} />
                    </div>
                  </div>
                ))
              ) : (
                <p className="text-sm text-muted-foreground">{t('No parts yet.')}</p>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Recent movements */}
        <Card className="gap-0 py-0">
          <SectionHeader title={t('Recent movements')} href="/stock_movements" />
          <CardContent className="p-0">
            {recent_movements.length > 0 ? (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{t('When')}</TableHead>
                    <TableHead>{t('Type')}</TableHead>
                    <TableHead>{t('Reference')}</TableHead>
                    <TableHead className="hidden md:table-cell">{t('Reason')}</TableHead>
                    <TableHead className="hidden md:table-cell">{t('By')}</TableHead>
                    <TableHead className="text-right">{t('Qty')}</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {recent_movements.map((movement) => (
                    <TableRow key={movement.id}>
                      <TableCell className="whitespace-nowrap text-sm text-muted-foreground" title={new Date(movement.created_at).toLocaleString(intlLocale())}>
                        {timeAgo(movement.created_at)}
                      </TableCell>
                      <TableCell>
                        <Badge className={MOVEMENT_META[movement.movement_type].className} variant="outline">
                          {MOVEMENT_META[movement.movement_type].label}
                        </Badge>
                      </TableCell>
                      <TableCell className="max-w-[220px]">
                        {partLink(movement.part_id, movement.reference)}
                        <div className="truncate text-xs text-muted-foreground">{movement.location_name}</div>
                      </TableCell>
                      <TableCell className="hidden max-w-[220px] truncate text-sm text-muted-foreground md:table-cell">
                        {movement.reason || '-'}
                      </TableCell>
                      <TableCell className="hidden whitespace-nowrap text-sm text-muted-foreground md:table-cell">
                        {movement.user_name || '-'}
                      </TableCell>
                      <TableCell className="text-right font-mono">
                        {movement.quantity_delta > 0 ? `+${movement.quantity_delta}` : movement.quantity_delta}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            ) : (
              <p className="p-6 text-sm text-muted-foreground">{t('No stock movements yet.')}</p>
            )}
          </CardContent>
        </Card>
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
