import { ArrowUpRight, Plus } from 'lucide-react'

import { usePermissions } from '@/hooks/use-permissions'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'

import { typeMeta } from './zone-meta'
import type { StorageLocationRecord } from './types'
import type { ZoneTree } from './use-zone-tree'
import { t } from '@/lib/i18n'

interface SubZoneGridProps {
  subZones: StorageLocationRecord[]
  tree: ZoneTree
  onSelect: (id: number) => void
  onAddHere: () => void
}

// The selected zone's direct children, as cards that navigate into them.
export function SubZoneGrid({ subZones, tree, onSelect, onAddHere }: SubZoneGridProps) {
  const { canWrite } = usePermissions()

  return (
    <div>
      <div className="mb-2 flex items-center justify-between">
        <h2 className="text-sm font-semibold">
          {t('Sub-zones')} <span className="font-normal text-muted-foreground">· {subZones.length}</span>
        </h2>
        {canWrite && (
          <Button variant="ghost" size="sm" className="text-xs text-muted-foreground" onClick={onAddHere}>
            <Plus className="size-3.5" />
            {t('Add here')}
          </Button>
        )}
      </div>
      {subZones.length > 0 ? (
        <div className="grid gap-3 sm:grid-cols-2">
          {subZones.map((z) => {
            const meta = typeMeta(z.location_type)
            const agg = tree.aggCounts(z.id)
            const childCount = (tree.childrenByParent.get(z.id) || []).length
            return (
              <Card key={z.id} className="cursor-pointer py-3 transition-colors hover:border-primary" onClick={() => onSelect(z.id)}>
                <CardContent className="flex items-center gap-3 px-4">
                  <div className={`flex size-9 shrink-0 items-center justify-center rounded-lg ${meta.className}`}>
                    <meta.icon className="size-4.5" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-sm font-semibold">{z.name}</div>
                    <div className="text-xs text-muted-foreground">
                      {meta.label}
                      {childCount > 0 && ` · ${childCount} sub-zone${childCount > 1 ? 's' : ''}`}
                      {` · ${agg.refs} ref${agg.refs !== 1 ? 's' : ''}`}
                    </div>
                  </div>
                  <ArrowUpRight className="size-4 shrink-0 text-muted-foreground" />
                </CardContent>
              </Card>
            )
          })}
        </div>
      ) : (
        <div className="rounded-lg border border-dashed p-5 text-center text-sm text-muted-foreground">
          {t('This zone has no sub-zone. It\'s a final storage location.')}
        </div>
      )}
    </div>
  )
}
