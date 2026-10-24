import { useMemo, useState } from 'react'
import { router, useForm } from '@inertiajs/react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Combobox, type ComboboxOption } from '@/components/ui/combobox'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { SupplierLookup, type LookupResult } from '@/components/supplier-lookup'

import type { CategoryOption, Order, PartOption } from './types'
import { t } from '@/lib/i18n'

interface AddLineDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  order: Order
  parts: PartOption[]
  categories: CategoryOption[]
  catalogEnabled: boolean
}

// Add a line from inventory, or look a part up in a supplier catalog and
// create it in the inventory as it's added. Remount (via `key`) to start
// from a blank form.
export function AddLineDialog({ open, onOpenChange, order, parts, categories, catalogEnabled }: AddLineDialogProps) {
  const [addMode, setAddMode] = useState<'inventory' | 'catalog'>('inventory')
  const [applied, setApplied] = useState<LookupResult | null>(null)
  const [catalogCategory, setCatalogCategory] = useState('')
  const [catalogQty, setCatalogQty] = useState('1')
  const [catalogSubmitting, setCatalogSubmitting] = useState(false)

  const partOptions = useMemo<ComboboxOption[]>(
    () => parts.map((p) => ({ value: String(p.id), label: `${p.reference} — ${p.name}` })),
    [parts]
  )

  const addForm = useForm({ order_line: { part_id: '', quantity: '1', unit_price: '' } })

  const submitAdd = (e: React.FormEvent) => {
    e.preventDefault()
    addForm.post(`/orders/${order.id}/order_lines`, {
      preserveScroll: true,
      onSuccess: () => {
        addForm.reset()
        onOpenChange(false)
      },
    })
  }

  const submitCatalog = (e: React.FormEvent) => {
    e.preventDefault()
    if (!applied || !catalogCategory) return
    setCatalogSubmitting(true)
    router.post(
      `/orders/${order.id}/order_lines/catalog`,
      {
        order_line: { quantity: catalogQty },
        category_id: catalogCategory,
        image_url: applied.image_url,
        supplier_sku: applied.supplier_sku,
        product_url: applied.product_url,
        price_breaks: applied.price_breaks ?? [],
        part: {
          name: applied.name,
          mpn: applied.mpn,
          manufacturer: applied.manufacturer,
          description: applied.description,
          value: applied.value,
          tolerance: applied.tolerance,
          voltage_rating: applied.voltage_rating,
          power_rating: applied.power_rating,
          package_type: applied.package_type,
          unit_price: applied.unit_price,
          rohs_compliant: applied.rohs_compliant,
        },
      },
      {
        preserveScroll: true,
        onSuccess: () => onOpenChange(false),
        onFinish: () => setCatalogSubmitting(false),
      }
    )
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{t('Add component')}</DialogTitle>
          <DialogDescription>
            {t('Pick a part from your inventory, or search a supplier catalog to add a new one.')}
          </DialogDescription>
        </DialogHeader>

        {catalogEnabled && (
          <div className="grid grid-cols-2 gap-1 rounded-lg bg-muted p-1">
            <Button
              type="button"
              size="sm"
              variant={addMode === 'inventory' ? 'default' : 'ghost'}
              onClick={() => setAddMode('inventory')}
            >
              {t('From inventory')}
            </Button>
            <Button
              type="button"
              size="sm"
              variant={addMode === 'catalog' ? 'default' : 'ghost'}
              onClick={() => setAddMode('catalog')}
            >
              {t('Search catalog')}
            </Button>
          </div>
        )}

        {addMode === 'inventory' ? (
          <form onSubmit={submitAdd}>
            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label>{t('Part')}</Label>
                <Combobox
                  options={partOptions}
                  value={addForm.data.order_line.part_id}
                  onValueChange={(value) => addForm.setData('order_line', { ...addForm.data.order_line, part_id: value })}
                  placeholder={t('Select a part')}
                  searchPlaceholder={t('Search parts…')}
                  className="w-full"
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-2">
                  <Label htmlFor="add-qty">{t('Quantity')}</Label>
                  <Input
                    id="add-qty"
                    type="number"
                    min={0}
                    step="any"
                    value={addForm.data.order_line.quantity}
                    onChange={(e) => addForm.setData('order_line', { ...addForm.data.order_line, quantity: e.target.value })}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="add-price">{t('Unit price')}</Label>
                  <Input
                    id="add-price"
                    type="number"
                    min={0}
                    step="0.0001"
                    placeholder={t('Auto')}
                    value={addForm.data.order_line.unit_price}
                    onChange={(e) => addForm.setData('order_line', { ...addForm.data.order_line, unit_price: e.target.value })}
                  />
                </div>
              </div>
              <p className="text-xs text-muted-foreground">{t('Leave the price blank to use the supplier’s price for this quantity, or the part price.')}</p>
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
                {t('Cancel')}
              </Button>
              <Button type="submit" disabled={addForm.processing || !addForm.data.order_line.part_id}>
                {t('Add to order')}
              </Button>
            </DialogFooter>
          </form>
        ) : (
          <form onSubmit={submitCatalog}>
            <div className="space-y-4 py-4">
              {applied ? (
                <div className="space-y-4">
                  <div className="rounded-lg border p-3">
                    <div className="flex items-center gap-2">
                      <span className="truncate font-medium">{applied.mpn ?? applied.name}</span>
                      {applied.manufacturer && (
                        <Badge variant="secondary" className="shrink-0 text-[10px]">{applied.manufacturer}</Badge>
                      )}
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        className="ml-auto h-7"
                        onClick={() => setApplied(null)}
                      >
                        {t('Change')}
                      </Button>
                    </div>
                    {applied.description && (
                      <p className="mt-1 truncate text-xs text-muted-foreground">{applied.description}</p>
                    )}
                  </div>

                  <div className="space-y-2">
                    <Label>{t('Category')}</Label>
                    <Select value={catalogCategory} onValueChange={setCatalogCategory}>
                      <SelectTrigger>
                        <SelectValue placeholder={t('Select a category')} />
                      </SelectTrigger>
                      <SelectContent>
                        {categories.map((c) => (
                          <SelectItem key={c.id} value={String(c.id)}>{c.name}</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <p className="text-xs text-muted-foreground">{t('Required — the new part is created in your inventory.')}</p>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="catalog-qty">{t('Quantity')}</Label>
                    <Input
                      id="catalog-qty"
                      type="number"
                      min={1}
                      value={catalogQty}
                      onChange={(e) => setCatalogQty(e.target.value)}
                    />
                  </div>
                </div>
              ) : (
                <SupplierLookup onApply={setApplied} />
              )}
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
                {t('Cancel')}
              </Button>
              <Button type="submit" disabled={!applied || !catalogCategory || catalogSubmitting}>
                {t('Create & add')}
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  )
}
