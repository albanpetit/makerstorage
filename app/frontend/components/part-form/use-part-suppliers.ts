import { useState } from 'react'

import { LookupResult, matchProviderSupplier } from '@/components/supplier-lookup'
import { EMPTY_SUPPLIER, NewSupplier, PartSupplier, PendingSupplier, Supplier } from './types'

// Encapsulates the supplier-management logic shared by the add and edit part
// dialogs: the pending-supplier list, the "add a supplier" form row, catalog
// pre-fill, and building the `part_suppliers_attributes` payload (including the
// `_destroy` markers for links the user removed while editing).
export function usePartSuppliers(suppliers: Supplier[]) {
  const [pendingSuppliers, setPendingSuppliers] = useState<PendingSupplier[]>([])
  // Ids of existing part-supplier links the user removed — sent back as
  // `_destroy` so the server tears them down. Empty in the add flow.
  const [removedSupplierIds, setRemovedSupplierIds] = useState<number[]>([])
  const [newSupplier, setNewSupplier] = useState<NewSupplier>({ ...EMPTY_SUPPLIER })

  const availableSuppliers = suppliers.filter(
    (s) => !pendingSuppliers.some((ps) => ps.supplier_id === s.id.toString())
  )

  // Seed the list from an existing part's supplier links (edit flow).
  const seedFromPartSuppliers = (partSuppliers: PartSupplier[]) => {
    setPendingSuppliers(
      partSuppliers.map((ps) => ({
        tempId: crypto.randomUUID(),
        id: ps.id,
        supplier_id: ps.supplier_id.toString(),
        supplier_name: ps.supplier_name,
        supplier_sku: ps.supplier_sku || '',
        unit_price: ps.unit_price?.toString() || '',
        lead_time_days: ps.lead_time_days?.toString() || '',
        url: ps.url || '',
        is_preferred: ps.is_preferred,
        notes: ps.notes || '',
      }))
    )
  }

  const addPendingSupplier = () => {
    const supplier = suppliers.find((s) => s.id.toString() === newSupplier.supplier_id)
    if (!supplier) return
    const others = newSupplier.is_preferred
      ? pendingSuppliers.map((ps) => ({ ...ps, is_preferred: false }))
      : pendingSuppliers
    setPendingSuppliers([
      ...others,
      { ...newSupplier, tempId: crypto.randomUUID(), supplier_name: supplier.name },
    ])
    setNewSupplier({ ...EMPTY_SUPPLIER })
  }

  const removePendingSupplier = (ps: PendingSupplier) => {
    setPendingSuppliers((prev) => prev.filter((p) => p.tempId !== ps.tempId))
    if (ps.id != null) setRemovedSupplierIds((ids) => [...ids, ps.id!])
  }

  const setPreferred = (tempId: string) =>
    setPendingSuppliers((prev) => prev.map((ps) => ({ ...ps, is_preferred: ps.tempId === tempId })))

  // Pre-fill from a catalog match: link the provider's own supplier
  // (Mouser/DigiKey) with the fetched price, SKU and product URL. Only runs when
  // that supplier exists in the org and the result carries data; re-running a
  // lookup refreshes the existing row instead of duplicating it. Calls `onApplied`
  // when a row was added or updated (used to reveal the suppliers section).
  const applySupplierFromResult = (result: LookupResult, onApplied?: () => void) => {
    const supplier = matchProviderSupplier(suppliers, result.provider)
    if (!supplier) return
    if (!result.unit_price && !result.supplier_sku && !result.product_url) return

    const supplierId = supplier.id.toString()
    setPendingSuppliers((prev) => {
      const existing = prev.find((ps) => ps.supplier_id === supplierId)
      if (existing) {
        return prev.map((ps) =>
          ps.supplier_id === supplierId
            ? {
                ...ps,
                supplier_sku: result.supplier_sku || ps.supplier_sku,
                unit_price: result.unit_price || ps.unit_price,
                url: result.product_url || ps.url,
              }
            : ps
        )
      }
      return [
        ...prev,
        {
          tempId: crypto.randomUUID(),
          supplier_id: supplierId,
          supplier_name: supplier.name,
          supplier_sku: result.supplier_sku || '',
          unit_price: result.unit_price || '',
          lead_time_days: '',
          url: result.product_url || '',
          is_preferred: prev.length === 0,
          notes: '',
        },
      ]
    })
    onApplied?.()
  }

  // Build the `part_suppliers_attributes` array for the submit payload. New rows
  // omit `id` entirely (so Rails creates them); existing rows carry it so Rails
  // updates in place, and removed rows come through as `_destroy` markers.
  const suppliersAttributes = () => [
    ...pendingSuppliers.map((ps) => ({
      ...(ps.id != null ? { id: ps.id } : {}),
      supplier_id: ps.supplier_id,
      supplier_sku: ps.supplier_sku || null,
      unit_price: ps.unit_price || null,
      lead_time_days: ps.lead_time_days || null,
      url: ps.url || null,
      is_preferred: ps.is_preferred,
      notes: ps.notes || null,
    })),
    ...removedSupplierIds.map((id) => ({ id, _destroy: true })),
  ]

  const reset = () => {
    setPendingSuppliers([])
    setRemovedSupplierIds([])
    setNewSupplier({ ...EMPTY_SUPPLIER })
  }

  return {
    pendingSuppliers,
    newSupplier,
    setNewSupplier,
    availableSuppliers,
    seedFromPartSuppliers,
    addPendingSupplier,
    removePendingSupplier,
    setPreferred,
    applySupplierFromResult,
    suppliersAttributes,
    reset,
  }
}

export type PartSuppliersController = ReturnType<typeof usePartSuppliers>
