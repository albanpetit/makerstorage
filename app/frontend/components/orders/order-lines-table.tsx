import { Link, router } from '@inertiajs/react'
import { AlertTriangle, Trash2 } from 'lucide-react'

import { usePermissions } from '@/hooks/use-permissions'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { formatMoney } from '@/pages/orders/helpers'
import { formatUnitPrice } from '@/lib/money'

import type { Order, OrderLine } from './types'
import { t } from '@/lib/i18n'
import { formatQuantity, isDecimalUnit, parseQuantity, quantityStep } from '@/lib/quantity'

// "Drawer A ×50, Drawer B ×50" — leaf zone name and quantity per allocation.
function allocationSummary(line: OrderLine): string {
  return line.allocations
    .map((a) => `${a.storage_location_path.split(' > ').pop()} ×${formatQuantity(a.quantity)}`)
    .join(', ')
}

interface OrderLinesTableProps {
  order: Order
  onEditAllocation: (line: OrderLine) => void
}

// The order's lines. While the order is editable, quantity and price save on
// blur and the storage column opens the allocation editor.
export function OrderLinesTable({ order, onEditAllocation }: OrderLinesTableProps) {
  const { canWrite } = usePermissions()

  const updateLine = (line: OrderLine, data: Record<string, string | number>) => {
    router.patch(`/orders/${order.id}/order_lines/${line.id}`, { order_line: data }, { preserveScroll: true })
  }

  const changeQuantity = (line: OrderLine, raw: string) => {
    const quantity = parseQuantity(raw)
    if (quantity === null || quantity <= 0 || quantity === line.quantity) return
    if (!isDecimalUnit(line.part.unit) && !Number.isInteger(quantity)) return
    updateLine(line, { quantity })
  }

  const changePrice = (line: OrderLine, raw: string) => {
    const value = raw.trim()
    const price = Number(value)
    if (value === '' || Number.isNaN(price) || price < 0 || price === line.unit_price) return
    updateLine(line, { unit_price: price })
  }

  return (
    <Card className="overflow-hidden py-0">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t('Component')}</TableHead>
            <TableHead className="text-right">{t('Quantity')}</TableHead>
            <TableHead className="text-right">{t('Unit price')}</TableHead>
            <TableHead className="text-right">{t('Subtotal')}</TableHead>
            <TableHead>{t('Storage on receipt')}</TableHead>
            {canWrite && order.editable && <TableHead className="w-10" />}
          </TableRow>
        </TableHeader>
        <TableBody>
          {order.lines.length === 0 ? (
            <TableRow>
              <TableCell colSpan={canWrite && order.editable ? 6 : 5} className="py-10 text-center text-sm text-muted-foreground">
                {t('No components yet. Add one from your inventory.')}
              </TableCell>
            </TableRow>
          ) : (
            order.lines.map((line) => (
              <TableRow key={line.id}>
                <TableCell>
                  <Link href={`/parts?highlight=${line.part.id}`} className="font-medium hover:underline">
                    {line.part.reference}
                  </Link>
                  <div className="max-w-[280px] truncate text-xs text-muted-foreground">{line.part.name}</div>
                </TableCell>
                <TableCell className="text-right">
                  {canWrite && order.editable ? (
                    <Input
                      type="number"
                      min={0}
                      step={quantityStep(line.part.unit)}
                      defaultValue={line.quantity}
                      className="ml-auto h-8 w-20 text-right font-mono"
                      onBlur={(e) => changeQuantity(line, e.target.value)}
                    />
                  ) : (
                    <span className="font-mono">{formatQuantity(line.quantity, line.part.unit)}</span>
                  )}
                </TableCell>
                <TableCell className="text-right">
                  {canWrite && order.editable ? (
                    <Input
                      // Remount when the server reprices the line (a quantity change moves it to another price break).
                      key={line.unit_price ?? ''}
                      type="number"
                      min={0}
                      step="0.0001"
                      defaultValue={line.unit_price ?? ''}
                      placeholder="—"
                      className="ml-auto h-8 w-24 text-right font-mono"
                      onBlur={(e) => changePrice(line, e.target.value)}
                    />
                  ) : (
                    <span className="font-mono">{line.unit_price != null ? `${formatUnitPrice(line.unit_price)} €` : '—'}</span>
                  )}
                </TableCell>
                <TableCell className="text-right font-mono">
                  {line.subtotal != null ? formatMoney(line.subtotal) : '—'}
                </TableCell>
                <TableCell>
                  {canWrite && order.editable ? (
                    <Button
                      type="button"
                      variant="ghost"
                      onClick={() => onEditAllocation(line)}
                      className="group h-auto max-w-[260px] flex-col items-start gap-1 p-0 text-left font-normal whitespace-normal hover:bg-transparent dark:hover:bg-transparent"
                    >
                      {line.allocations.length === 0 ? (
                        <span className="text-xs text-muted-foreground underline decoration-dotted group-hover:text-foreground">
                          {t('Set zones…')}
                        </span>
                      ) : (
                        <>
                          <span className="text-xs">{allocationSummary(line)}</span>
                          {line.allocated_quantity !== line.quantity && (
                            <Badge variant="outline" className="bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400">
                              <AlertTriangle className="size-3" /> {formatQuantity(line.allocated_quantity)}/{formatQuantity(line.quantity, line.part.unit)}
                            </Badge>
                          )}
                        </>
                      )}
                    </Button>
                  ) : line.allocations.length === 0 ? (
                    <span className="text-xs text-muted-foreground">—</span>
                  ) : (
                    <span className="text-xs">{allocationSummary(line)}</span>
                  )}
                </TableCell>
                {canWrite && order.editable && (
                  <TableCell>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      aria-label={t('Remove line')}
                      onClick={() => router.delete(`/orders/${order.id}/order_lines/${line.id}`, { preserveScroll: true })}
                    >
                      <Trash2 className="size-4 text-muted-foreground" />
                    </Button>
                  </TableCell>
                )}
              </TableRow>
            ))
          )}
        </TableBody>
      </Table>
    </Card>
  )
}
