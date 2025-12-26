import { Head, useForm, Link, router } from '@inertiajs/react'
import { FormEventHandler } from 'react'
import { ArrowLeft } from 'lucide-react'

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

interface NewPartProps {
  categories: Category[]
  footprints: Footprint[]
  suppliers: Supplier[]
}

export default function NewPart({ categories, footprints, suppliers }: NewPartProps) {
  const { data, setData, post, processing, errors } = useForm({
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
      preferred_supplier_id: '',
      supplier_sku: '',
      unit_price: '',
      min_stock_threshold: '0',
      target_stock: '',
      lead_time_days: '',
      status: 'active',
      rohs_compliant: false,
      storage_notes: '',
    },
  })

  const breadcrumbs = [
    { label: 'Parts', href: '/parts' },
    { label: 'New Part' },
  ]

  const submit: FormEventHandler = (e) => {
    e.preventDefault()
    post('/parts')
  }

  const handleSelectChange = (field: string, value: string) => {
    setData('part', { ...data.part, [field]: value === 'none' ? '' : value })
  }

  return (
    <AppLayout breadcrumbs={breadcrumbs}>
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
                  {errors['part.category'] && <FieldError>{errors['part.category']}</FieldError>}
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

          {/* Supplier & Pricing */}
          <Card>
            <CardHeader>
              <CardTitle>Supplier & Pricing</CardTitle>
              <CardDescription>Purchasing information</CardDescription>
            </CardHeader>
            <CardContent>
              <FieldGroup className="grid gap-4 md:grid-cols-2">
                {/* Preferred Supplier */}
                <Field>
                  <FieldLabel>
                    <Label>Preferred Supplier</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Select
                      value={data.part.preferred_supplier_id}
                      onValueChange={(value) => handleSelectChange('preferred_supplier_id', value)}
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Select a supplier" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="none">None</SelectItem>
                        {suppliers.map((supplier) => (
                          <SelectItem key={supplier.id} value={supplier.id.toString()}>
                            {supplier.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </FieldContent>
                  {errors['part.preferred_supplier_id'] && <FieldError>{errors['part.preferred_supplier_id']}</FieldError>}
                </Field>

                {/* Supplier SKU */}
                <Field>
                  <FieldLabel>
                    <Label htmlFor="supplier_sku">Supplier SKU</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="supplier_sku"
                      value={data.part.supplier_sku}
                      onChange={(e) => setData('part', { ...data.part, supplier_sku: e.target.value })}
                      placeholder="Supplier's part number"
                    />
                  </FieldContent>
                  {errors['part.supplier_sku'] && <FieldError>{errors['part.supplier_sku']}</FieldError>}
                </Field>

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

                {/* Lead Time */}
                <Field>
                  <FieldLabel>
                    <Label htmlFor="lead_time_days">Lead Time (days)</Label>
                  </FieldLabel>
                  <FieldContent>
                    <Input
                      id="lead_time_days"
                      type="number"
                      min="0"
                      value={data.part.lead_time_days}
                      onChange={(e) => setData('part', { ...data.part, lead_time_days: e.target.value })}
                      placeholder="e.g., 7"
                    />
                  </FieldContent>
                  {errors['part.lead_time_days'] && <FieldError>{errors['part.lead_time_days']}</FieldError>}
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
