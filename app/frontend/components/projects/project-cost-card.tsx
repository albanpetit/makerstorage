import { router } from '@inertiajs/react'
import { FormEvent, useState } from 'react'
import { AlertTriangle, ChevronDown, ChevronUp, Coins, Download } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { formatMoney, formatUnitPrice } from '@/lib/money'
import { intlLocale, t, tn } from '@/lib/i18n'

export interface ProjectCostRow {
  part: { id: number; reference: string; name: string }
  required: number
  from_stock: number
  to_buy: number
  stock_unit_price: number | null
  buy_unit_price: number | null
  supplier: string | null
  cost: number
  priced: boolean
}

export interface ProjectCostEstimate {
  quantity: number
  stock_value: number
  purchase_cost: number
  total: number
  per_unit: number
  complete: boolean
  unpriced_count: number
  unmatched_count: number
  unmatched: { id: number; label: string | null; quantity: number }[]
  rows: ProjectCostRow[]
}

export interface ProjectCostData {
  currency: string
  quantities: number[]
  estimates: ProjectCostEstimate[]
}

// Highest number of copies the server prices (ProjectCost::MAX_QUANTITY).
const MAX_QUANTITY = 100_000

// What N copies of the project cost (ProjectCost): 1, 10 and 100 plus a typed
// quantity, split between the stock it takes and what must be bought, with
// the part by part detail of the selected quantity.
export function ProjectCostCard({ projectId, cost }: { projectId: number; cost: ProjectCostData }) {
  const [selected, setSelected] = useState(cost.estimates.find((estimate) => estimate.quantity === 10)?.quantity ?? cost.quantities[0])
  const [custom, setCustom] = useState('')
  const [showDetail, setShowDetail] = useState(false)

  const estimate = cost.estimates.find((entry) => entry.quantity === selected) ?? cost.estimates[0]
  if (!estimate || (estimate.rows.length === 0 && estimate.unmatched_count === 0)) return null

  const money = (value: number) => formatMoney(value, cost.currency)
  const customQuantity = Number(custom)
  const customValid = Number.isInteger(customQuantity) && customQuantity >= 1 && customQuantity <= MAX_QUANTITY

  function priceCustom(event: FormEvent) {
    event.preventDefault()
    if (!customValid) return
    router.reload({
      only: ['cost'],
      data: { cost_quantity: customQuantity },
      onSuccess: () => {
        setSelected(customQuantity)
        setCustom('')
      },
    })
  }

  return (
    <Card className="gap-4">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Coins className="size-4 text-muted-foreground" />
          {t('Cost to build')}
        </CardTitle>
        <CardDescription>
          {t('From the prices on file: parts in stock at their unit price, parts to buy at the supplier’s price break for the quantity bought.')}
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <form onSubmit={priceCustom} className="flex items-center gap-2">
          <Input
            type="number"
            min={1}
            max={MAX_QUANTITY}
            inputMode="numeric"
            value={custom}
            onChange={(event) => setCustom(event.target.value)}
            placeholder={t('Other quantity')}
            aria-label={t('Number of copies to price')}
            className="h-8 w-40"
          />
          <Button type="submit" size="sm" variant="outline" disabled={!customValid}>
            {t('Estimate')}
          </Button>
        </form>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t('Copies')}</TableHead>
              <TableHead className="hidden text-right sm:table-cell">{t('From stock')}</TableHead>
              <TableHead className="hidden text-right sm:table-cell">{t('To buy')}</TableHead>
              <TableHead className="text-right">{t('Total')}</TableHead>
              <TableHead className="text-right">{t('Per copy')}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {cost.estimates.map((entry) => (
              <TableRow
                key={entry.quantity}
                data-state={entry.quantity === estimate.quantity ? 'selected' : undefined}
                className="cursor-pointer"
                onClick={() => setSelected(entry.quantity)}
              >
                <TableCell className="font-mono font-medium">× {entry.quantity.toLocaleString(intlLocale())}</TableCell>
                <TableCell className="hidden text-right font-mono text-muted-foreground sm:table-cell">{money(entry.stock_value)}</TableCell>
                <TableCell className="hidden text-right font-mono sm:table-cell">{money(entry.purchase_cost)}</TableCell>
                <TableCell className="text-right font-mono font-semibold">
                  {!entry.complete && (
                    <AlertTriangle className="mr-1 inline size-3.5 text-amber-600 dark:text-amber-400" aria-label={t('Incomplete')} />
                  )}
                  {money(entry.total)}
                </TableCell>
                <TableCell className="text-right font-mono font-semibold">{money(entry.per_unit)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>

        {!estimate.complete && (
          <p className="flex items-start gap-2 text-sm text-amber-700 dark:text-amber-400">
            <AlertTriangle className="mt-0.5 size-4 shrink-0" />
            <span>
              {[
                estimate.unpriced_count > 0 && tn('{count} part has no price', '{count} parts have no price', estimate.unpriced_count),
                estimate.unmatched_count > 0 && tn('{count} line is not in the inventory', '{count} lines are not in the inventory', estimate.unmatched_count),
              ].filter(Boolean).join(' · ')}
              {' '}
              {t('(left out: the totals are a minimum).')}
            </span>
          </p>
        )}

        <div className="flex flex-wrap items-center gap-2">
          <Button size="sm" variant="ghost" onClick={() => setShowDetail(!showDetail)}>
            {showDetail ? <ChevronUp className="size-4" /> : <ChevronDown className="size-4" />}
            {tn('Part by part for {count} copy', 'Part by part for {count} copies', estimate.quantity, { count: estimate.quantity.toLocaleString(intlLocale()) })}
          </Button>
          <Button size="sm" variant="ghost" asChild>
            <a href={`/projects/${projectId}/cost?quantity=${estimate.quantity}`}>
              <Download className="size-4" />
              {t('Export CSV')}
            </a>
          </Button>
        </div>

        {showDetail && (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>{t('Part')}</TableHead>
                <TableHead className="text-right">{t('Needed')}</TableHead>
                <TableHead className="text-right">{t('From stock')}</TableHead>
                <TableHead className="text-right">{t('To buy')}</TableHead>
                <TableHead className="text-right">{t('Unit price')}</TableHead>
                <TableHead className="text-right">{t('Cost')}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {estimate.rows.map((row) => (
                <TableRow key={row.part.id}>
                  <TableCell>
                    <a href={`/parts/${row.part.id}`} className="font-mono text-xs text-muted-foreground hover:underline">
                      {row.part.reference}
                    </a>
                    <div className="max-w-[280px] truncate text-sm" title={row.part.name}>{row.part.name}</div>
                  </TableCell>
                  <TableCell className="text-right font-mono">{row.required}</TableCell>
                  <TableCell className="text-right font-mono text-muted-foreground">{row.from_stock}</TableCell>
                  <TableCell className="text-right font-mono">{row.to_buy > 0 ? row.to_buy : '—'}</TableCell>
                  <TableCell className="text-right text-sm">
                    {row.priced ? (
                      <UnitPrices row={row} />
                    ) : (
                      <Badge variant="outline" className="border-amber-500/50 text-amber-700 dark:text-amber-400">{t('No price')}</Badge>
                    )}
                  </TableCell>
                  <TableCell className="text-right font-mono">{row.priced ? money(row.cost) : '—'}</TableCell>
                </TableRow>
              ))}
              {estimate.unmatched.map((line) => (
                <TableRow key={`line-${line.id}`}>
                  <TableCell className="max-w-[280px] truncate text-sm text-muted-foreground" title={line.label ?? undefined}>
                    {line.label ?? '—'}
                  </TableCell>
                  <TableCell className="text-right font-mono">{line.quantity}</TableCell>
                  <TableCell colSpan={3} className="text-right">
                    <Badge variant="outline" className="border-red-500/50 text-red-700 dark:text-red-400">{t('Not in inventory')}</Badge>
                  </TableCell>
                  <TableCell className="text-right font-mono">—</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}

// The price of the units bought (with their supplier), and of the stock taken
// when it differs.
function UnitPrices({ row }: { row: ProjectCostRow }) {
  const buy = row.to_buy > 0 && row.buy_unit_price !== null ? row.buy_unit_price : null
  const stock = row.from_stock > 0 && row.stock_unit_price !== null ? row.stock_unit_price : null

  return (
    <div className="font-mono">
      {buy !== null && (
        <div>
          {formatUnitPrice(buy)}
          {row.supplier && <span className="ml-1 font-sans text-xs text-muted-foreground">{row.supplier}</span>}
        </div>
      )}
      {stock !== null && (buy === null || stock !== buy) && (
        <div className="text-xs text-muted-foreground">
          {t('stock {price}', { price: formatUnitPrice(stock) })}
        </div>
      )}
    </div>
  )
}
