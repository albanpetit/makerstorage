import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'
import { t, tn, intlLocale } from '@/lib/i18n'

export interface ActivityDay {
  date: string
  in: number
  out: number
  adjustment: number
}

// Same hues as the movement badges; dark mode uses a deeper green so the three
// stay apart on the dark surface.
const SERIES = [
  { key: 'in', get label() { return t('In') }, className: 'bg-emerald-500 dark:bg-emerald-600' },
  { key: 'adjustment', get label() { return t('Adjustment') }, className: 'bg-amber-500' },
  { key: 'out', get label() { return t('Out') }, className: 'bg-rose-500' },
] as const

const CHART_HEIGHT = 160

function dayLabel(iso: string, options: Intl.DateTimeFormatOptions) {
  // Dates are plain days in the organization's time zone: read them as local
  // noon so no time zone shifts them to the day before.
  return new Date(`${iso}T12:00:00`).toLocaleDateString(intlLocale(), options)
}

/**
 * Stacked daily bars of stock movements by type, with a tooltip per day.
 */
export function ActivityChart({ days }: { days: ActivityDay[] }) {
  const totals = days.map((day) => day.in + day.out + day.adjustment)
  const max = Math.max(1, ...totals)

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-4 text-xs text-muted-foreground">
        {SERIES.map((series) => (
          <span key={series.key} className="flex items-center gap-1.5">
            <span className={`size-2.5 rounded-sm ${series.className}`} />
            {series.label}
          </span>
        ))}
      </div>

      <div className="relative" style={{ height: CHART_HEIGHT }}>
        <div className="pointer-events-none absolute inset-x-0 top-0 border-t border-dashed" />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 border-t" />
        <span className="pointer-events-none absolute -top-2 right-0 bg-card pl-1 text-[10px] text-muted-foreground">
          {max}
        </span>

        <div className="flex h-full items-end gap-[2px] pr-6">
          {days.map((day, index) => {
            const total = totals[index]
            return (
              <Tooltip key={day.date}>
                <TooltipTrigger asChild>
                  <div
                    className="group flex h-full min-w-0 flex-1 flex-col justify-end rounded-sm hover:bg-muted/60"
                    aria-label={tn('{date}: {count} movement', '{date}: {count} movements', total, { date: dayLabel(day.date, { day: 'numeric', month: 'long' }) })}
                  >
                    <div
                      className="flex flex-col-reverse gap-[2px] overflow-hidden rounded-t-[4px]"
                      style={{ height: `${(total / max) * 100}%` }}
                    >
                      {SERIES.map((series) =>
                        day[series.key] > 0 ? (
                          <div
                            key={series.key}
                            className={series.className}
                            style={{ flexGrow: day[series.key], minHeight: 2 }}
                          />
                        ) : null,
                      )}
                    </div>
                  </div>
                </TooltipTrigger>
                <TooltipContent>
                  <div className="font-medium">{dayLabel(day.date, { weekday: 'short', day: 'numeric', month: 'short' })}</div>
                  {total === 0 ? (
                    <div>{t('No movements')}</div>
                  ) : (
                    SERIES.filter((series) => day[series.key] > 0).map((series) => (
                      <div key={series.key}>
                        {series.label}: {day[series.key]}
                      </div>
                    ))
                  )}
                </TooltipContent>
              </Tooltip>
            )
          })}
        </div>
      </div>

      <div className="flex justify-between pr-6 text-[10px] text-muted-foreground">
        <span>{days.length > 0 && dayLabel(days[0].date, { day: 'numeric', month: 'short' })}</span>
        <span>{t('Today')}</span>
      </div>
    </div>
  )
}
