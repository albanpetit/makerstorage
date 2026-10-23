import { Link } from '@inertiajs/react'
import { Badge } from '@/components/ui/badge'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { t, tn, intlLocale } from '@/lib/i18n'
import { formatUnitPrice } from '@/lib/money'
import { ORDER_STATUS_META } from '@/pages/orders/helpers'

// One priced order line for the part (PartsController#serialize_price_history).
export interface PricePoint {
  order_id: number
  order_reference: string | null
  status: keyof typeof ORDER_STATUS_META
  supplier_name: string
  date: string
  quantity: number
  unit_price: number
}

const CHART_HEIGHT = 72
// Purchases listed under the chart, most recent first.
const LISTED = 5

function dayLabel(iso: string, options: Intl.DateTimeFormatOptions) {
  // Plain days: read them as local noon so no time zone moves them.
  return new Date(`${iso}T12:00:00`).toLocaleDateString(intlLocale(), options)
}

/**
 * The part's purchase prices: last, lowest and quantity-weighted average, a
 * line of every purchase in order (with a tooltip per purchase), and the most
 * recent ones linking to their orders.
 */
export function PriceHistory({ points }: { points: PricePoint[] }) {
  if (points.length === 0) {
    return (
      <p className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">
        {t('No purchase price yet: prices on this part’s orders show up here.')}
      </p>
    )
  }

  const prices = points.map((point) => point.unit_price)
  const min = Math.min(...prices)
  const max = Math.max(...prices)
  const units = points.reduce((sum, point) => sum + point.quantity, 0)
  const average = points.reduce((sum, point) => sum + point.quantity * point.unit_price, 0) / units
  const last = points[points.length - 1]
  const first = points[0]
  const change = first.unit_price > 0 ? ((last.unit_price - first.unit_price) / first.unit_price) * 100 : 0

  // Leave a margin above and below so flat or extreme points stay visible.
  const span = max - min || max || 1
  const low = min - span * 0.15
  const high = max + span * 0.15
  const x = (index: number) => (points.length === 1 ? 50 : (index / (points.length - 1)) * 100)
  const y = (price: number) => 100 - ((price - low) / (high - low)) * 100

  const stats = [
    { label: t('Last'), value: formatUnitPrice(last.unit_price) },
    { label: t('Lowest'), value: formatUnitPrice(min) },
    { label: t('Average'), value: formatUnitPrice(average) },
  ]

  return (
    <div className="space-y-3 rounded-lg border p-3">
      <div className="grid grid-cols-3 gap-2">
        {stats.map((stat) => (
          <div key={stat.label}>
            <div className="text-[11px] text-muted-foreground">{stat.label}</div>
            <div className="font-mono text-sm font-semibold">{stat.value}</div>
          </div>
        ))}
      </div>

      {points.length > 1 && (
        <div>
          <div className="relative" style={{ height: CHART_HEIGHT }}>
            <div className="pointer-events-none absolute inset-x-0 bottom-0 border-t" />
            <svg className="absolute inset-0 size-full overflow-visible" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden>
              <polyline
                points={points.map((point, index) => `${x(index)},${y(point.unit_price)}`).join(' ')}
                fill="none"
                className="stroke-blue-600 dark:stroke-blue-400"
                strokeWidth={2}
                strokeLinejoin="round"
                vectorEffect="non-scaling-stroke"
              />
            </svg>
            {points.map((point, index) => (
              <Tooltip key={`${point.order_id}-${index}`}>
                <TooltipTrigger asChild>
                  <div
                    tabIndex={0}
                    className="group absolute flex size-5 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full"
                    style={{ left: `${x(index)}%`, top: `${y(point.unit_price)}%` }}
                    aria-label={t('{date}: {price} from {supplier}', {
                      date: dayLabel(point.date, { day: 'numeric', month: 'long', year: 'numeric' }),
                      price: formatUnitPrice(point.unit_price),
                      supplier: point.supplier_name,
                    })}
                  >
                    <span className="size-2 rounded-full bg-blue-600 ring-2 ring-card transition-transform group-hover:scale-150 group-focus-visible:scale-150 dark:bg-blue-400" />
                  </div>
                </TooltipTrigger>
                <TooltipContent>
                  <div className="font-medium">{formatUnitPrice(point.unit_price)}</div>
                  <div>{dayLabel(point.date, { day: 'numeric', month: 'short', year: 'numeric' })} · {point.supplier_name}</div>
                  <div>{tn('{count} unit', '{count} units', point.quantity)}</div>
                </TooltipContent>
              </Tooltip>
            ))}
          </div>
          <div className="mt-1.5 flex justify-between text-[10px] text-muted-foreground">
            <span>{dayLabel(first.date, { month: 'short', year: 'numeric' })}</span>
            <span>
              {change === 0
                ? t('Unchanged')
                : t('{change} since the first purchase', { change: `${change > 0 ? '+' : ''}${change.toLocaleString(intlLocale(), { maximumFractionDigits: 0 })} %` })}
            </span>
            <span>{dayLabel(last.date, { month: 'short', year: 'numeric' })}</span>
          </div>
        </div>
      )}

      <div className="-mb-1 divide-y border-t">
        {points.slice(-LISTED).reverse().map((point, index) => {
          const meta = ORDER_STATUS_META[point.status]
          return (
            <div key={`${point.order_id}-${index}`} className="flex items-center gap-2 py-2 text-xs">
              <span className="shrink-0 font-mono text-muted-foreground">{dayLabel(point.date, { day: '2-digit', month: '2-digit', year: '2-digit' })}</span>
              <Link href={`/orders/${point.order_id}`} className="min-w-0 flex-1 truncate hover:underline">
                {point.supplier_name}
                {point.order_reference ? ` · ${point.order_reference}` : ''}
              </Link>
              {point.status !== 'received' && (
                <Badge variant="outline" className={meta.className}>{meta.label}</Badge>
              )}
              <span className="shrink-0 text-muted-foreground">× {point.quantity}</span>
              <span className="shrink-0 font-mono font-semibold">{formatUnitPrice(point.unit_price)}</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
