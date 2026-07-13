import { Head, useForm, Link, router } from '@inertiajs/react'
import { FormEventHandler, useState } from 'react'
import { ArrowLeft, Plus, Trash2, Star, ExternalLink } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { FlashMessages } from '@/components/flash-messages'
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
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { CategorySelect } from '@/components/category-select'
import { TagPicker } from '@/components/tag-picker'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Badge } from '@/components/ui/badge'

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

interface Tag {
  id: number
  name: string
  color: string | null
}

interface PartSupplier {
  id: number
  supplier_id: number
  supplier_name: string
  supplier_sku: string | null
  unit_price: number | null
  lead_time_days: number | null
  url: string | null
  is_preferred: boolean
  notes: string | null
}

interface Part {
  id: number
  name: string
  mpn: string | null
  sku: string | null
  barcode: string | null
  manufacturer: string | null
  description: string | null
  value: string | null
  tolerance: string | null
  voltage_rating: string | null
  power_rating: string | null
  package_type: string | null
  status: string
  unit_price: number | null
  min_stock_threshold: number
  target_stock: number | null
  rohs_compliant: boolean
  storage_notes: string | null
  category_id: number
  footprint_id: number | null
  tag_ids: number[]
  part_suppliers: PartSupplier[]
}

interface EditPartProps {
  part: Part
  categories: Category[]
  footprints: Footprint[]
  suppliers: Supplier[]
  tags: Tag[]
}

export default function EditPart({ part, categories, footprints, suppliers, tags }: EditPartProps) {
  const [showAddSupplier, setShowAddSupplier] = useState(false)

  const { data, setData, put, processing, errors } = useForm({
    part: {
      name: part.name,
      mpn: part.mpn || '',
      sku: part.sku || '',
      barcode: part.barcode || '',
      manufacturer: part.manufacturer || '',
      description: part.description || '',
      value: part.value || '',
      tolerance: part.tolerance || '',
      voltage_rating: part.voltage_rating || '',
      power_rating: part.power_rating || '',
      package_type: part.package_type || '',
      category_id: part.category_id.toString(),
      footprint_id: part.footprint_id?.toString() || '',
      unit_price: part.unit_price?.toString() || '',
      min_stock_threshold: part.min_stock_threshold.toString(),
      target_stock: part.target_stock?.toString() || '',
      status: part.status,
      rohs_compliant: part.rohs_compliant,
      storage_notes: part.storage_notes || '',
      tag_ids: part.tag_ids,
    },
  })

  const newSupplierForm = useForm({
    part_supplier: {
      supplier_id: '',
      supplier_sku: '',
      unit_price: '',
      lead_time_days: '',
      url: '',
      is_preferred: false,
      notes: '',
    },
  })

  const submit: FormEventHandler = (e) => {
    e.preventDefault()
    put(`/parts/${part.id}`)
  }

  const handleSelectChange = (field: string, value: string) => {
    setData('part', { ...data.part, [field]: value === 'none' ? '' : value })
  }

  const handleAddSupplier: FormEventHandler = (e) => {
    e.preventDefault()
    newSupplierForm.post(`/parts/${part.id}/part_suppliers`, {
      onSuccess: () => {
        setShowAddSupplier(false)
        newSupplierForm.reset()
      },
    })
  }

  const handleRemoveSupplier = (supplierId: number) => {
    if (confirm('Are you sure you want to remove this supplier?')) {
      router.delete(`/parts/${part.id}/part_suppliers/${supplierId}`)
    }
  }

  const handleSetPreferred = (supplierId: number) => {
    router.post(`/parts/${part.id}/part_suppliers/${supplierId}/set_preferred`)
  }

  // Get available suppliers (not already linked)
  const availableSuppliers = suppliers.filter(
    (s) => !part.part_suppliers.some((ps) => ps.supplier_id === s.id)
  )

  return (
    <AppLayout>
      <Head title={`Edit ${part.name}`} />

      <div className="space-y-6">
        {/* Header */}
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" asChild>
            <Link href="/parts">
              <ArrowLeft className="size-4" />
            </Link>
          </Button>
          <div>
            <h1 className="text-2xl font-bold tracking-tight">Edit Part</h1>
            <p className="text-muted-foreground">{part.name}</p>
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
                <Field className="md:col-span-2">
                  <FieldLabel>
                    <Label htmlFor="name">Name *</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="name"
                      value={data.part.name}
                      onChange={(e) => setData('part', { ...data.part, name: e.target.value })}
                      required
                    />
                  </FieldContent>
                  {errors['part.name'] && <FieldError>{errors['part.name']}</FieldError>}
                </Field>

                <Field>
                  <FieldLabel>
                    <Label htmlFor="mpn">Manufacturer Part Number (MPN)</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="mpn"
                      value={data.part.mpn}
                      onChange={(e) => setData('part', { ...data.part, mpn: e.target.value })}
                    />
                  </FieldContent>
                  {errors['part.mpn'] && <FieldError>{errors['part.mpn']}</FieldError>}
                </Field>

                <Field>
                  <FieldLabel>
                    <Label htmlFor="sku">Internal SKU</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="sku"
                      value={data.part.sku}
                      onChange={(e) => setData('part', { ...data.part, sku: e.target.value })}
                    />
                  </FieldContent>
                  {errors['part.sku'] && <FieldError>{errors['part.sku']}</FieldError>}
                </Field>

                <Field>
                  <FieldLabel>
                    <Label htmlFor="barcode">Barcode</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="barcode"
                      value={data.part.barcode}
                      onChange={(e) => setData('part', { ...data.part, barcode: e.target.value })}
                    />
                  </FieldContent>
                  {errors['part.barcode'] && <FieldError>{errors['part.barcode']}</FieldError>}
                </Field>

                <Field>
                  <FieldLabel>
                    <Label htmlFor="manufacturer">Manufacturer</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="manufacturer"
                      value={data.part.manufacturer}
                      onChange={(e) => setData('part', { ...data.part, manufacturer: e.target.value })}
                    />
                  </FieldContent>
                  {errors['part.manufacturer'] && <FieldError>{errors['part.manufacturer']}</FieldError>}
                </Field>

                <Field className="md:col-span-2">
                  <FieldLabel>
                    <Label htmlFor="description">Description</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Textarea
                      id="description"
                      value={data.part.description}
                      onChange={(e) => setData('part', { ...data.part, description: e.target.value })}
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
                <Field>
                  <FieldLabel>
                    <Label>Category *</Label>
                  </FieldLabel>
                  <FieldContent>
                    <CategorySelect
                      categories={categories}
                      value={data.part.category_id}
                      onValueChange={(value) => handleSelectChange('category_id', value)}
                    />
                  </FieldContent>
                  {errors['part.category_id'] && <FieldError>{errors['part.category_id']}</FieldError>}
                </Field>

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

                <Field className="md:col-span-2">
                  <FieldLabel>
                    <Label>Tags</Label>
                  </FieldLabel>
                  <FieldContent>
                    <TagPicker
                      tags={tags}
                      value={data.part.tag_ids}
                      onChange={(ids) => setData('part', { ...data.part, tag_ids: ids })}
                    />
                  </FieldContent>
                  {errors['part.tag_ids'] && <FieldError>{errors['part.tag_ids']}</FieldError>}
                </Field>

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

                <Field>
                  <FieldLabel>
                    <Label htmlFor="package_type">Package Type</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="package_type"
                      value={data.part.package_type}
                      onChange={(e) => setData('part', { ...data.part, package_type: e.target.value })}
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
                <Field>
                  <FieldLabel>
                    <Label htmlFor="value">Value</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="value"
                      value={data.part.value}
                      onChange={(e) => setData('part', { ...data.part, value: e.target.value })}
                    />
                  </FieldContent>
                  {errors['part.value'] && <FieldError>{errors['part.value']}</FieldError>}
                </Field>

                <Field>
                  <FieldLabel>
                    <Label htmlFor="tolerance">Tolerance</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="tolerance"
                      value={data.part.tolerance}
                      onChange={(e) => setData('part', { ...data.part, tolerance: e.target.value })}
                    />
                  </FieldContent>
                  {errors['part.tolerance'] && <FieldError>{errors['part.tolerance']}</FieldError>}
                </Field>

                <Field>
                  <FieldLabel>
                    <Label htmlFor="voltage_rating">Voltage Rating</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="voltage_rating"
                      value={data.part.voltage_rating}
                      onChange={(e) => setData('part', { ...data.part, voltage_rating: e.target.value })}
                    />
                  </FieldContent>
                  {errors['part.voltage_rating'] && <FieldError>{errors['part.voltage_rating']}</FieldError>}
                </Field>

                <Field>
                  <FieldLabel>
                    <Label htmlFor="power_rating">Power Rating</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="power_rating"
                      value={data.part.power_rating}
                      onChange={(e) => setData('part', { ...data.part, power_rating: e.target.value })}
                    />
                  </FieldContent>
                  {errors['part.power_rating'] && <FieldError>{errors['part.power_rating']}</FieldError>}
                </Field>

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

          {/* Pricing & Stock */}
          <Card>
            <CardHeader>
              <CardTitle>Pricing & Stock</CardTitle>
              <CardDescription>Inventory thresholds and pricing</CardDescription>
            </CardHeader>
            <CardContent>
              <FieldGroup className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
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
                    />
                  </FieldContent>
                  {errors['part.unit_price'] && <FieldError>{errors['part.unit_price']}</FieldError>}
                </Field>

                <Field>
                  <FieldLabel>
                    <Label htmlFor="min_stock_threshold">Min Stock Threshold</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="min_stock_threshold"
                      type="number"
                      min="0"
                      value={data.part.min_stock_threshold}
                      onChange={(e) => setData('part', { ...data.part, min_stock_threshold: e.target.value })}
                    />
                  </FieldContent>
                  {errors['part.min_stock_threshold'] && <FieldError>{errors['part.min_stock_threshold']}</FieldError>}
                </Field>

                <Field>
                  <FieldLabel>
                    <Label htmlFor="target_stock">Target Stock</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="target_stock"
                      type="number"
                      min="1"
                      value={data.part.target_stock}
                      onChange={(e) => setData('part', { ...data.part, target_stock: e.target.value })}
                    />
                  </FieldContent>
                  {errors['part.target_stock'] && <FieldError>{errors['part.target_stock']}</FieldError>}
                </Field>

                <Field className="md:col-span-2 lg:col-span-4">
                  <FieldLabel>
                    <Label htmlFor="storage_notes">Storage Notes</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Textarea
                      id="storage_notes"
                      value={data.part.storage_notes}
                      onChange={(e) => setData('part', { ...data.part, storage_notes: e.target.value })}
                      rows={2}
                    />
                  </FieldContent>
                  {errors['part.storage_notes'] && <FieldError>{errors['part.storage_notes']}</FieldError>}
                </Field>
              </FieldGroup>
            </CardContent>
          </Card>

          {/* Actions */}
          <div className="flex items-center justify-end gap-4">
            <Button variant="outline" asChild>
              <Link href="/parts">Cancel</Link>
            </Button>
            <Button type="submit" disabled={processing}>
              {processing ? 'Saving...' : 'Save Changes'}
            </Button>
          </div>
        </form>

        {/* Suppliers Section */}
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <div>
                <CardTitle>Suppliers</CardTitle>
                <CardDescription>Manage suppliers for this part</CardDescription>
              </div>
              {availableSuppliers.length > 0 && !showAddSupplier && (
                <Button onClick={() => setShowAddSupplier(true)} size="sm">
                  <Plus className="mr-2 size-4" />
                  Add Supplier
                </Button>
              )}
            </div>
          </CardHeader>
          <CardContent>
            {/* Add Supplier Form */}
            {showAddSupplier && (
              <form onSubmit={handleAddSupplier} className="mb-6 p-4 border rounded-lg bg-muted/50">
                <h4 className="font-medium mb-4">Add New Supplier</h4>
                <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
                  <div className="space-y-2">
                    <Label>Supplier *</Label>
                    <Select
                      value={newSupplierForm.data.part_supplier.supplier_id}
                      onValueChange={(value) =>
                        newSupplierForm.setData('part_supplier', {
                          ...newSupplierForm.data.part_supplier,
                          supplier_id: value,
                        })
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
                      value={newSupplierForm.data.part_supplier.supplier_sku}
                      onChange={(e) =>
                        newSupplierForm.setData('part_supplier', {
                          ...newSupplierForm.data.part_supplier,
                          supplier_sku: e.target.value,
                        })
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
                      value={newSupplierForm.data.part_supplier.unit_price}
                      onChange={(e) =>
                        newSupplierForm.setData('part_supplier', {
                          ...newSupplierForm.data.part_supplier,
                          unit_price: e.target.value,
                        })
                      }
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="new_lead_time">Lead Time (days)</Label>
                    <Input
                      id="new_lead_time"
                      type="number"
                      min="0"
                      value={newSupplierForm.data.part_supplier.lead_time_days}
                      onChange={(e) =>
                        newSupplierForm.setData('part_supplier', {
                          ...newSupplierForm.data.part_supplier,
                          lead_time_days: e.target.value,
                        })
                      }
                    />
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="new_url">Product URL</Label>
                    <Input
                      id="new_url"
                      type="url"
                      value={newSupplierForm.data.part_supplier.url}
                      onChange={(e) =>
                        newSupplierForm.setData('part_supplier', {
                          ...newSupplierForm.data.part_supplier,
                          url: e.target.value,
                        })
                      }
                      placeholder="https://..."
                    />
                  </div>

                  <div className="flex items-end space-x-2">
                    <Checkbox
                      id="new_is_preferred"
                      checked={newSupplierForm.data.part_supplier.is_preferred}
                      onCheckedChange={(checked) =>
                        newSupplierForm.setData('part_supplier', {
                          ...newSupplierForm.data.part_supplier,
                          is_preferred: checked === true,
                        })
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
                      newSupplierForm.reset()
                    }}
                  >
                    Cancel
                  </Button>
                  <Button type="submit" disabled={newSupplierForm.processing}>
                    {newSupplierForm.processing ? 'Adding...' : 'Add Supplier'}
                  </Button>
                </div>
              </form>
            )}

            {/* Suppliers Table */}
            {part.part_suppliers.length > 0 ? (
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
                    {part.part_suppliers.map((ps) => (
                      <TableRow key={ps.id}>
                        <TableCell className="font-medium">
                          {ps.supplier_name}
                        </TableCell>
                        <TableCell>
                          <div className="flex items-center gap-2">
                            {ps.supplier_sku || '-'}
                            {ps.url && (
                              <a
                                href={ps.url}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="text-muted-foreground hover:text-foreground"
                              >
                                <ExternalLink className="size-3" />
                              </a>
                            )}
                          </div>
                        </TableCell>
                        <TableCell className="text-right font-mono">
                          {ps.unit_price != null ? `$${ps.unit_price.toFixed(2)}` : '-'}
                        </TableCell>
                        <TableCell className="text-right">
                          {ps.lead_time_days != null ? `${ps.lead_time_days} days` : '-'}
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
                                variant="ghost"
                                size="icon"
                                onClick={() => handleSetPreferred(ps.id)}
                                title="Set as preferred"
                              >
                                <Star className="size-4" />
                              </Button>
                            )}
                            <Button
                              variant="ghost"
                              size="icon"
                              onClick={() => handleRemoveSupplier(ps.id)}
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
                No suppliers linked to this part yet.
                {availableSuppliers.length > 0 && (
                  <>
                    {' '}
                    <Button variant="link" onClick={() => setShowAddSupplier(true)} className="p-0">
                      Add one now
                    </Button>
                  </>
                )}
              </p>
            )}
          </CardContent>
        </Card>
      </div>
    </AppLayout>
  )
}
