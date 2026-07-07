import { Head, useForm, Link } from '@inertiajs/react'
import { FormEventHandler, useState } from 'react'
import { ArrowLeft, Plus, Trash2, Star } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Checkbox } from '@/components/ui/checkbox'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Field,
  FieldContent,
  FieldError,
  FieldGroup,
  FieldLabel,
} from '@/components/ui/field'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Badge } from '@/components/ui/badge'
import { FlashMessages } from '@/components/flash-messages'

interface Category {
  id: number
  name: string
}

interface Footprint {
  id: number
  name: string
  mounting_type: string | null
}

interface Supplier {
  id: number
  name: string
}

interface PendingSupplier {
  tempId: string
  supplier_id: string
  supplier_name: string
  supplier_sku: string
  unit_price: string
  lead_time_days: string
  url: string
  is_preferred: boolean
  notes: string
}

interface NewPartProps {
  categories: Category[]
  footprints: Footprint[]
  suppliers: Supplier[]
}

export default function NewPart({ categories, footprints, suppliers }: NewPartProps) {
  const [pendingSuppliers, setPendingSuppliers] = useState<PendingSupplier[]>([])
  const [showAddSupplier, setShowAddSupplier] = useState(false)
  const [newSupplier, setNewSupplier] = useState<Omit<PendingSupplier, 'tempId' | 'supplier_name'>>({
    supplier_id: '',
    supplier_sku: '',
    unit_price: '',
    lead_time_days: '',
    url: '',
    is_preferred: false,
    notes: '',
  })

  const { data, setData, post, processing, errors, transform } = useForm({
    part: {
      name: '',
      mpn: '',
      sku: '',
      barcode: '',
      manufacturer: '',
      description: '',
      value: '',
      tolerance: '',
      voltage_rating: '',
      power_rating: '',
      package_type: '',
      category_id: '',
      footprint_id: '',
      unit_price: '',
      min_stock_threshold: '0',
      target_stock: '',
      status: 'active',
      rohs_compliant: false,
      storage_notes: '',
    },
  })

  // Transform data before submission to include part_suppliers_attributes
  transform((formData) => ({
    part: {
      ...formData.part,
      part_suppliers_attributes: pendingSuppliers.map((ps) => ({
        supplier_id: ps.supplier_id,
        supplier_sku: ps.supplier_sku || null,
        unit_price: ps.unit_price || null,
        lead_time_days: ps.lead_time_days || null,
        url: ps.url || null,
        is_preferred: ps.is_preferred,
        notes: ps.notes || null,
      })),
    },
  }))

  const submit: FormEventHandler = (e) => {
    e.preventDefault()
    post('/parts')
  }

  const handleSelectChange = (field: string, value: string) => {
    setData('part', { ...data.part, [field]: value === 'none' ? '' : value })
  }

  const handleAddSupplier = () => {
    if (!newSupplier.supplier_id) return

    const supplier = suppliers.find((s) => s.id.toString() === newSupplier.supplier_id)
    if (!supplier) return

    // If marking as preferred, unset other preferred suppliers
    let updatedPendingSuppliers = pendingSuppliers
    if (newSupplier.is_preferred) {
      updatedPendingSuppliers = pendingSuppliers.map((ps) => ({ ...ps, is_preferred: false }))
    }

    setPendingSuppliers([
      ...updatedPendingSuppliers,
      {
        ...newSupplier,
        tempId: crypto.randomUUID(),
        supplier_name: supplier.name,
      },
    ])

    // Reset form
    setNewSupplier({
      supplier_id: '',
      supplier_sku: '',
      unit_price: '',
      lead_time_days: '',
      url: '',
      is_preferred: false,
      notes: '',
    })
    setShowAddSupplier(false)
  }

  const handleRemoveSupplier = (tempId: string) => {
    setPendingSuppliers(pendingSuppliers.filter((ps) => ps.tempId !== tempId))
  }

  const handleSetPreferred = (tempId: string) => {
    setPendingSuppliers(
      pendingSuppliers.map((ps) => ({
        ...ps,
        is_preferred: ps.tempId === tempId,
      }))
    )
  }

  // Get available suppliers (not already added)
  const availableSuppliers = suppliers.filter(
    (s) => !pendingSuppliers.some((ps) => ps.supplier_id === s.id.toString())
  )

  return (
    <AppLayout>
      <Head title="New Part" />

      <div className="space-y-6">
        {/* Header */}
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" asChild>
            <Link href="/parts">
              <ArrowLeft className="size-4" />
            </Link>
          </Button>
          <div>
            <h1 className="text-2xl font-bold tracking-tight">New Part</h1>
            <p className="text-muted-foreground">Add a new part to your inventory</p>
          </div>
        </div>

        <FlashMessages errors={errors} />

        <form onSubmit={submit} className="space-y-6">
          {/* Basic Information */}
          <Card>
            <CardHeader>
              <CardTitle>Basic Information</CardTitle>
              <CardDescription>Essential details about the part</CardDescription>
            </CardHeader>
            <CardContent>
              <FieldGroup className="grid gap-4 md:grid-cols-2">
                {/* Name */}
                <Field className="md:col-span-2">
                  <FieldLabel>
                    <Label htmlFor="name">Name *</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="name"
                      value={data.part.name}
                      onChange={(e) => setData('part', { ...data.part, name: e.target.value })}
                      placeholder="e.g., 10K Resistor"
                      required
                      autoFocus
                    />
                  </FieldContent>
                  {errors['part.name'] && <FieldError>{errors['part.name']}</FieldError>}
                </Field>

                {/* MPN */}
                <Field>
                  <FieldLabel>
                    <Label htmlFor="mpn">Manufacturer Part Number (MPN)</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="mpn"
                      value={data.part.mpn}
                      onChange={(e) => setData('part', { ...data.part, mpn: e.target.value })}
                      placeholder="e.g., RC0805FR-0710KL"
                    />
                  </FieldContent>
                  {errors['part.mpn'] && <FieldError>{errors['part.mpn']}</FieldError>}
                </Field>

                {/* SKU */}
                <Field>
                  <FieldLabel>
                    <Label htmlFor="sku">Internal SKU</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="sku"
                      value={data.part.sku}
                      onChange={(e) => setData('part', { ...data.part, sku: e.target.value })}
                      placeholder="e.g., RES-10K-0805"
                    />
                  </FieldContent>
                  {errors['part.sku'] && <FieldError>{errors['part.sku']}</FieldError>}
                </Field>

                {/* Barcode */}
                <Field>
                  <FieldLabel>
                    <Label htmlFor="barcode">Barcode</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="barcode"
                      value={data.part.barcode}
                      onChange={(e) => setData('part', { ...data.part, barcode: e.target.value })}
                      placeholder="Scan or enter barcode"
                    />
                  </FieldContent>
                  {errors['part.barcode'] && <FieldError>{errors['part.barcode']}</FieldError>}
                </Field>

                {/* Manufacturer */}
                <Field>
                  <FieldLabel>
                    <Label htmlFor="manufacturer">Manufacturer</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="manufacturer"
                      value={data.part.manufacturer}
                      onChange={(e) => setData('part', { ...data.part, manufacturer: e.target.value })}
                      placeholder="e.g., Yageo"
                    />
                  </FieldContent>
                  {errors['part.manufacturer'] && <FieldError>{errors['part.manufacturer']}</FieldError>}
                </Field>

                {/* Description */}
                <Field className="md:col-span-2">
                  <FieldLabel>
                    <Label htmlFor="description">Description</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Textarea
                      id="description"
                      value={data.part.description}
                      onChange={(e) => setData('part', { ...data.part, description: e.target.value })}
                      placeholder="Detailed description of the part"
                      rows={3}
                    />
                  </FieldContent>
                  {errors['part.description'] && <FieldError>{errors['part.description']}</FieldError>}
                </Field>
              </FieldGroup>
            </CardContent>
          </Card>

          {/* Classification */}
          <Card>
            <CardHeader>
              <CardTitle>Classification</CardTitle>
              <CardDescription>Category and physical characteristics</CardDescription>
            </CardHeader>
            <CardContent>
              <FieldGroup className="grid gap-4 md:grid-cols-2">
                {/* Category */}
                <Field>
                  <FieldLabel>
                    <Label>Category *</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Select
                      value={data.part.category_id}
                      onValueChange={(value) => handleSelectChange('category_id', value)}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Select a category" />
                      </SelectTrigger>
                      <SelectContent>
                        {categories.map((category) => (
                          <SelectItem key={category.id} value={category.id.toString()}>
                            {category.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </FieldContent>
                  {errors['part.category_id'] && <FieldError>{errors['part.category_id']}</FieldError>}
                </Field>

                {/* Footprint */}
                <Field>
                  <FieldLabel>
                    <Label>Footprint</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Select
                      value={data.part.footprint_id}
                      onValueChange={(value) => handleSelectChange('footprint_id', value)}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Select a footprint" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="none">None</SelectItem>
                        {footprints.map((footprint) => (
                          <SelectItem key={footprint.id} value={footprint.id.toString()}>
                            {footprint.name}
                            {footprint.mounting_type && ` (${footprint.mounting_type})`}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </FieldContent>
                  {errors['part.footprint_id'] && <FieldError>{errors['part.footprint_id']}</FieldError>}
                </Field>

                {/* Status */}
                <Field>
                  <FieldLabel>
                    <Label>Status</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Select
                      value={data.part.status}
                      onValueChange={(value) => handleSelectChange('status', value)}
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="active">Active</SelectItem>
                        <SelectItem value="discontinued">Discontinued</SelectItem>
                        <SelectItem value="obsolete">Obsolete</SelectItem>
                      </SelectContent>
                    </Select>
                  </FieldContent>
                  {errors['part.status'] && <FieldError>{errors['part.status']}</FieldError>}
                </Field>

                {/* Package Type */}
                <Field>
                  <FieldLabel>
                    <Label htmlFor="package_type">Package Type</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="package_type"
                      value={data.part.package_type}
                      onChange={(e) => setData('part', { ...data.part, package_type: e.target.value })}
                      placeholder="e.g., Tape & Reel"
                    />
                  </FieldContent>
                  {errors['part.package_type'] && <FieldError>{errors['part.package_type']}</FieldError>}
                </Field>
              </FieldGroup>
            </CardContent>
          </Card>

          {/* Technical Specifications */}
          <Card>
            <CardHeader>
              <CardTitle>Technical Specifications</CardTitle>
              <CardDescription>Electrical and physical properties</CardDescription>
            </CardHeader>
            <CardContent>
              <FieldGroup className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                {/* Value */}
                <Field>
                  <FieldLabel>
                    <Label htmlFor="value">Value</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="value"
                      value={data.part.value}
                      onChange={(e) => setData('part', { ...data.part, value: e.target.value })}
                      placeholder="e.g., 10K, 100nF"
                    />
                  </FieldContent>
                  {errors['part.value'] && <FieldError>{errors['part.value']}</FieldError>}
                </Field>

                {/* Tolerance */}
                <Field>
                  <FieldLabel>
                    <Label htmlFor="tolerance">Tolerance</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="tolerance"
                      value={data.part.tolerance}
                      onChange={(e) => setData('part', { ...data.part, tolerance: e.target.value })}
                      placeholder="e.g., 1%, 5%"
                    />
                  </FieldContent>
                  {errors['part.tolerance'] && <FieldError>{errors['part.tolerance']}</FieldError>}
                </Field>

                {/* Voltage Rating */}
                <Field>
                  <FieldLabel>
                    <Label htmlFor="voltage_rating">Voltage Rating</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="voltage_rating"
                      value={data.part.voltage_rating}
                      onChange={(e) => setData('part', { ...data.part, voltage_rating: e.target.value })}
                      placeholder="e.g., 50V, 100V"
                    />
                  </FieldContent>
                  {errors['part.voltage_rating'] && <FieldError>{errors['part.voltage_rating']}</FieldError>}
                </Field>

                {/* Power Rating */}
                <Field>
                  <FieldLabel>
                    <Label htmlFor="power_rating">Power Rating</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="power_rating"
                      value={data.part.power_rating}
                      onChange={(e) => setData('part', { ...data.part, power_rating: e.target.value })}
                      placeholder="e.g., 0.125W, 1W"
                    />
                  </FieldContent>
                  {errors['part.power_rating'] && <FieldError>{errors['part.power_rating']}</FieldError>}
                </Field>

                {/* RoHS Compliant */}
                <Field className="md:col-span-2 lg:col-span-4">
                  <div className="flex items-center space-x-2">
                    <Checkbox
                      id="rohs_compliant"
                      checked={data.part.rohs_compliant}
                      onCheckedChange={(checked) =>
                        setData('part', { ...data.part, rohs_compliant: checked === true })
                      }
                    />
                    <Label htmlFor="rohs_compliant" className="font-normal cursor-pointer">
                      RoHS Compliant
                    </Label>
                  </div>
                </Field>
              </FieldGroup>
            </CardContent>
          </Card>

          {/* Pricing */}
          <Card>
            <CardHeader>
              <CardTitle>Pricing</CardTitle>
              <CardDescription>Default unit price (supplier-specific prices can be set below)</CardDescription>
            </CardHeader>
            <CardContent>
              <FieldGroup className="grid gap-4 md:grid-cols-2">
                {/* Unit Price */}
                <Field>
                  <FieldLabel>
                    <Label htmlFor="unit_price">Unit Price ($)</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="unit_price"
                      type="number"
                      step="0.01"
                      min="0"
                      value={data.part.unit_price}
                      onChange={(e) => setData('part', { ...data.part, unit_price: e.target.value })}
                      placeholder="0.00"
                    />
                  </FieldContent>
                  {errors['part.unit_price'] && <FieldError>{errors['part.unit_price']}</FieldError>}
                </Field>
              </FieldGroup>
            </CardContent>
          </Card>

          {/* Stock Management */}
          <Card>
            <CardHeader>
              <CardTitle>Stock Management</CardTitle>
              <CardDescription>Inventory thresholds and notes</CardDescription>
            </CardHeader>
            <CardContent>
              <FieldGroup className="grid gap-4 md:grid-cols-2">
                {/* Min Stock Threshold */}
                <Field>
                  <FieldLabel>
                    <Label htmlFor="min_stock_threshold">Minimum Stock Threshold</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="min_stock_threshold"
                      type="number"
                      min="0"
                      value={data.part.min_stock_threshold}
                      onChange={(e) => setData('part', { ...data.part, min_stock_threshold: e.target.value })}
                      placeholder="0"
                    />
                  </FieldContent>
                  {errors['part.min_stock_threshold'] && <FieldError>{errors['part.min_stock_threshold']}</FieldError>}
                </Field>

                {/* Target Stock */}
                <Field>
                  <FieldLabel>
                    <Label htmlFor="target_stock">Target Stock Level</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="target_stock"
                      type="number"
                      min="1"
                      value={data.part.target_stock}
                      onChange={(e) => setData('part', { ...data.part, target_stock: e.target.value })}
                      placeholder="e.g., 100"
                    />
                  </FieldContent>
                  {errors['part.target_stock'] && <FieldError>{errors['part.target_stock']}</FieldError>}
                </Field>

                {/* Storage Notes */}
                <Field className="md:col-span-2">
                  <FieldLabel>
                    <Label htmlFor="storage_notes">Storage Notes</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Textarea
                      id="storage_notes"
                      value={data.part.storage_notes}
                      onChange={(e) => setData('part', { ...data.part, storage_notes: e.target.value })}
                      placeholder="Special storage requirements or handling instructions"
                      rows={2}
                    />
                  </FieldContent>
                  {errors['part.storage_notes'] && <FieldError>{errors['part.storage_notes']}</FieldError>}
                </Field>
              </FieldGroup>
            </CardContent>
          </Card>

          {/* Suppliers Section */}
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle>Suppliers</CardTitle>
                  <CardDescription>Link suppliers to this part (optional)</CardDescription>
                </div>
                {availableSuppliers.length > 0 && !showAddSupplier && (
                  <Button type="button" onClick={() => setShowAddSupplier(true)} size="sm">
                    <Plus className="mr-2 size-4" />
                    Add Supplier
                  </Button>
                )}
              </div>
            </CardHeader>
            <CardContent>
              {/* Add Supplier Form */}
              {showAddSupplier && (
                <div className="mb-6 p-4 border rounded-lg bg-muted/50">
                  <h4 className="font-medium mb-4">Add Supplier</h4>
                  <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                    <div className="space-y-2">
                      <Label>Supplier *</Label>
                      <Select
                        value={newSupplier.supplier_id}
                        onValueChange={(value) =>
                          setNewSupplier({ ...newSupplier, supplier_id: value })
                        }
                      >
                        <SelectTrigger>
                          <SelectValue placeholder="Select supplier" />
                        </SelectTrigger>
                        <SelectContent>
                          {availableSuppliers.map((supplier) => (
                            <SelectItem key={supplier.id} value={supplier.id.toString()}>
                              {supplier.name}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="new_supplier_sku">Supplier SKU</Label>
                      <Input
                        id="new_supplier_sku"
                        value={newSupplier.supplier_sku}
                        onChange={(e) =>
                          setNewSupplier({ ...newSupplier, supplier_sku: e.target.value })
                        }
                        placeholder="Supplier's part number"
                      />
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="new_unit_price">Unit Price ($)</Label>
                      <Input
                        id="new_unit_price"
                        type="number"
                        step="0.01"
                        min="0"
                        value={newSupplier.unit_price}
                        onChange={(e) =>
                          setNewSupplier({ ...newSupplier, unit_price: e.target.value })
                        }
                      />
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="new_lead_time">Lead Time (days)</Label>
                      <Input
                        id="new_lead_time"
                        type="number"
                        min="0"
                        value={newSupplier.lead_time_days}
                        onChange={(e) =>
                          setNewSupplier({ ...newSupplier, lead_time_days: e.target.value })
                        }
                      />
                    </div>

                    <div className="space-y-2">
                      <Label htmlFor="new_url">Product URL</Label>
                      <Input
                        id="new_url"
                        type="url"
                        value={newSupplier.url}
                        onChange={(e) =>
                          setNewSupplier({ ...newSupplier, url: e.target.value })
                        }
                        placeholder="https://..."
                      />
                    </div>

                    <div className="flex items-end space-x-2">
                      <Checkbox
                        id="new_is_preferred"
                        checked={newSupplier.is_preferred}
                        onCheckedChange={(checked) =>
                          setNewSupplier({ ...newSupplier, is_preferred: checked === true })
                        }
                      />
                      <Label htmlFor="new_is_preferred" className="font-normal cursor-pointer">
                        Preferred supplier
                      </Label>
                    </div>
                  </div>

                  <div className="flex justify-end gap-2 mt-4">
                    <Button
                      type="button"
                      variant="outline"
                      onClick={() => {
                        setShowAddSupplier(false)
                        setNewSupplier({
                          supplier_id: '',
                          supplier_sku: '',
                          unit_price: '',
                          lead_time_days: '',
                          url: '',
                          is_preferred: false,
                          notes: '',
                        })
                      }}
                    >
                      Cancel
                    </Button>
                    <Button type="button" onClick={handleAddSupplier} disabled={!newSupplier.supplier_id}>
                      Add Supplier
                    </Button>
                  </div>
                </div>
              )}

              {/* Pending Suppliers Table */}
              {pendingSuppliers.length > 0 ? (
                <div className="rounded-md border">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Supplier</TableHead>
                        <TableHead>Supplier SKU</TableHead>
                        <TableHead className="text-right">Unit Price</TableHead>
                        <TableHead className="text-right">Lead Time</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead className="w-[100px]">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {pendingSuppliers.map((ps) => (
                        <TableRow key={ps.tempId}>
                          <TableCell className="font-medium">{ps.supplier_name}</TableCell>
                          <TableCell>{ps.supplier_sku || '-'}</TableCell>
                          <TableCell className="text-right font-mono">
                            {ps.unit_price ? `$${parseFloat(ps.unit_price).toFixed(2)}` : '-'}
                          </TableCell>
                          <TableCell className="text-right">
                            {ps.lead_time_days ? `${ps.lead_time_days} days` : '-'}
                          </TableCell>
                          <TableCell>
                            {ps.is_preferred && (
                              <Badge variant="default">
                                <Star className="mr-1 size-3" />
                                Preferred
                              </Badge>
                            )}
                          </TableCell>
                          <TableCell>
                            <div className="flex items-center gap-1">
                              {!ps.is_preferred && (
                                <Button
                                  type="button"
                                  variant="ghost"
                                  size="icon"
                                  onClick={() => handleSetPreferred(ps.tempId)}
                                  title="Set as preferred"
                                >
                                  <Star className="size-4" />
                                </Button>
                              )}
                              <Button
                                type="button"
                                variant="ghost"
                                size="icon"
                                onClick={() => handleRemoveSupplier(ps.tempId)}
                                title="Remove supplier"
                              >
                                <Trash2 className="size-4 text-destructive" />
                              </Button>
                            </div>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              ) : (
                <p className="text-muted-foreground text-center py-8">
                  No suppliers added yet.
                  {availableSuppliers.length > 0 && !showAddSupplier && (
                    <>
                      {' '}
                      <Button
                        type="button"
                        variant="link"
                        onClick={() => setShowAddSupplier(true)}
                        className="p-0"
                      >
                        Add one now
                      </Button>
                    </>
                  )}
                </p>
              )}
            </CardContent>
          </Card>

          {/* Actions */}
          <div className="flex items-center justify-end gap-4">
            <Button variant="outline" asChild>
              <Link href="/parts">Cancel</Link>
            </Button>
            <Button type="submit" disabled={processing}>
              {processing ? 'Creating...' : 'Create Part'}
            </Button>
          </div>
        </form>
      </div>
    </AppLayout>
  )
}
