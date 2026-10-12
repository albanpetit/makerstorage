import { ArrowRightLeft, GripVertical } from 'lucide-react'

import { usePermissions } from '@/hooks/use-permissions'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Checkbox } from '@/components/ui/checkbox'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

import type { PartStorageEntry } from './types'

interface ZoneComponentsTableProps {
  entries: PartStorageEntry[]
  selectedPartIds: Set<number>
  onSelectionChange: (ids: Set<number>) => void
  onToggle: (partId: number) => void
  draggingPartIds: number[] | null
  onDragStart: (partId: number) => void
  onDragEnd: () => void
  onBulkMove: () => void
}

// Parts stored directly in the selected zone. Rows can be checked for a bulk
// move, or dragged onto a zone in the tree.
export function ZoneComponentsTable({
  entries, selectedPartIds, onSelectionChange, onToggle,
  draggingPartIds, onDragStart, onDragEnd, onBulkMove,
}: ZoneComponentsTableProps) {
  const { canWrite } = usePermissions()

  return (
    <div>
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-sm font-semibold">
          Components stored here <span className="font-normal text-muted-foreground">· {entries.length}</span>
        </h2>
        {canWrite && entries.length > 0 && (
          selectedPartIds.size > 0 ? (
            <div className="flex items-center gap-1.5">
              <span className="text-xs text-muted-foreground">{selectedPartIds.size} selected</span>
              <Button size="sm" variant="outline" onClick={onBulkMove}>
                <ArrowRightLeft className="size-3.5" />
                Move to…
              </Button>
              <Button size="sm" variant="ghost" className="text-muted-foreground" onClick={() => onSelectionChange(new Set())}>
                Clear
              </Button>
            </div>
          ) : (
            <span className="hidden text-xs text-muted-foreground lg:inline">Drag a row onto a zone, or select to move in bulk</span>
          )
        )}
      </div>
      {entries.length > 0 ? (
        <Card className="gap-0 py-0">
          <Table>
            <TableHeader>
              <TableRow>
                {canWrite && (
                  <TableHead className="w-9">
                    <Checkbox
                      aria-label="Select all components"
                      checked={entries.every((ps) => selectedPartIds.has(ps.part.id))}
                      onCheckedChange={(checked) =>
                        onSelectionChange(checked === true ? new Set(entries.map((ps) => ps.part.id)) : new Set())
                      }
                    />
                  </TableHead>
                )}
                <TableHead>Reference</TableHead>
                <TableHead>Name</TableHead>
                <TableHead>Package</TableHead>
                <TableHead className="text-right">Stock</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {entries.map((ps) => {
                const checked = selectedPartIds.has(ps.part.id)
                const dragging = draggingPartIds?.includes(ps.part.id) ?? false
                return (
                  <TableRow
                    key={ps.part.id}
                    data-state={checked ? 'selected' : undefined}
                    draggable={canWrite}
                    onDragStart={canWrite ? (e) => {
                      onDragStart(ps.part.id)
                      e.dataTransfer.effectAllowed = 'move'
                      e.dataTransfer.setData('text/plain', ps.part.reference)
                    } : undefined}
                    onDragEnd={onDragEnd}
                    className={`${canWrite ? 'cursor-grab' : ''} ${dragging ? 'opacity-50' : ''}`}
                  >
                    {canWrite && (
                      <TableCell className="w-9">
                        <div className="flex items-center gap-1">
                          <GripVertical className="size-3.5 shrink-0 text-muted-foreground/50" />
                          <Checkbox
                            aria-label={`Select ${ps.part.reference}`}
                            checked={checked}
                            onCheckedChange={() => onToggle(ps.part.id)}
                          />
                        </div>
                      </TableCell>
                    )}
                    <TableCell className="font-mono text-sm font-semibold">{ps.part.reference}</TableCell>
                    <TableCell className="text-sm text-muted-foreground">{ps.part.name}</TableCell>
                    <TableCell>
                      {ps.part.package_type && (
                        <span className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">{ps.part.package_type}</span>
                      )}
                    </TableCell>
                    <TableCell className="text-right font-mono font-semibold">{ps.quantity}</TableCell>
                  </TableRow>
                )
              })}
            </TableBody>
          </Table>
        </Card>
      ) : (
        <div className="rounded-lg border border-dashed p-5 text-center text-sm text-muted-foreground">
          No component directly in this zone — they're stored in the sub-zones above.
        </div>
      )}
    </div>
  )
}
