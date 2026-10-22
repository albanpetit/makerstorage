import { FormEvent } from 'react'
import { Info } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle, CardFooter } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'

import type { InventoryForm } from './types'
import { t } from '@/lib/i18n'

// Organization-wide stock defaults.
export function InventorySection({ form }: { form: InventoryForm }) {
  const submitInventory = (e: FormEvent) => {
    e.preventDefault()
    form.patch('/settings', { preserveScroll: true })
  }

  return (
    <form onSubmit={submitInventory} className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">{t('Inventory')}</h2>
        <p className="max-w-xl text-sm text-muted-foreground">
          {t('Default behavior applied across the organization\'s stock.')}
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>{t('Stock defaults')}</CardTitle>
        </CardHeader>
        <CardContent className="divide-y">
          <div className="flex items-center justify-between gap-4 py-3 first:pt-0">
            <div>
              <div className="text-sm font-medium">{t('Default low-stock threshold')}</div>
              <div className="text-xs text-muted-foreground">{t('Applied to new components unless overridden.')}</div>
            </div>
            <Input
              type="number"
              min={0}
              className="w-28 text-center font-mono"
              value={form.data.organization.default_low_stock_threshold}
              onChange={(e) => form.setData('organization', {
                ...form.data.organization,
                default_low_stock_threshold: Number(e.target.value) || 0,
              })}
            />
          </div>
          <div className="flex items-center justify-between gap-4 py-3">
            <div>
              <div className="text-sm font-medium">{t('Allow negative stock')}</div>
              <div className="text-xs text-muted-foreground">{t('Permit stock movements that exceed the available quantity.')}</div>
            </div>
            <Switch
              checked={form.data.organization.allow_negative_stock}
              onCheckedChange={(checked) => form.setData('organization', { ...form.data.organization, allow_negative_stock: checked })}
            />
          </div>
          <div className="flex items-center justify-between gap-4 py-3">
            <div>
              <div className="text-sm font-medium">{t('Reserve stock for projects')}</div>
              <div className="text-xs text-muted-foreground">{t('Confirmed projects hold their BOM quantities until built, so other projects only count what\'s left.')}</div>
            </div>
            <Switch
              checked={form.data.organization.stock_reservations_enabled}
              onCheckedChange={(checked) => form.setData('organization', { ...form.data.organization, stock_reservations_enabled: checked })}
            />
          </div>
          <div className="flex items-center justify-between gap-4 py-3 last:pb-0">
            <div>
              <div className="text-sm font-medium">{t('Default loan duration (days)')}</div>
              <div className="text-xs text-muted-foreground">{t('Suggested due date for new loans; it can be changed on each loan.')}</div>
            </div>
            <Input
              type="number"
              min={1}
              max={3650}
              className="w-28 text-center font-mono"
              value={form.data.organization.default_loan_days}
              onChange={(e) => form.setData('organization', {
                ...form.data.organization,
                default_loan_days: Number(e.target.value) || 0,
              })}
            />
          </div>
        </CardContent>
        <CardFooter className="justify-end border-t">
          <Button type="submit" disabled={form.processing}>{t('Save')}</Button>
        </CardFooter>
      </Card>
      <div className="flex items-center gap-2 text-xs text-muted-foreground">
        <Info className="size-3.5 shrink-0" />
        {t('Per-component thresholds set on individual parts always take priority over this default.')}
      </div>
    </form>
  )
}
