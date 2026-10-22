import { Badge } from '@/components/ui/badge'
import { Card } from '@/components/ui/card'

import { MOVEMENT_META, formatDate } from './zone-meta'
import type { RecentMovement } from './types'
import { t } from '@/lib/i18n'

// The latest stock movements in the selected zone and its sub-zones.
export function ZoneHistory({ movements }: { movements: RecentMovement[] }) {
  return (
    <div>
      <div className="mb-2 flex items-center justify-between">
        <h2 className="text-sm font-semibold">
          {t('Zone history')} <span className="font-normal text-muted-foreground">{t('· subtree included')}</span>
        </h2>
      </div>
      {movements.length > 0 ? (
        <Card className="gap-0 py-0 divide-y">
          {movements.map((m, i) => (
            <div key={i} className="flex items-center gap-3 px-4 py-2.5 text-sm">
              <Badge className={MOVEMENT_META[m.movement_type].className} variant="outline">
                {MOVEMENT_META[m.movement_type].label}
              </Badge>
              <span className="shrink-0 font-mono font-semibold">{m.part_reference}</span>
              <span className="min-w-0 flex-1 truncate text-muted-foreground">{m.reason}</span>
              <span className="shrink-0 whitespace-nowrap text-xs text-muted-foreground">{formatDate(m.created_at)}</span>
              <span className="w-12 shrink-0 text-right font-mono font-semibold">
                {m.quantity_delta > 0 ? `+${m.quantity_delta}` : m.quantity_delta}
              </span>
            </div>
          ))}
        </Card>
      ) : (
        <div className="rounded-lg border border-dashed p-5 text-center text-sm text-muted-foreground">
          {t('No movement recorded for this zone yet.')}
        </div>
      )}
    </div>
  )
}
