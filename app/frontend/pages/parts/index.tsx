import { Head, Link } from '@inertiajs/react'
import { Plus, Search, Package, Pencil } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { FlashMessages } from '@/components/flash-messages'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

interface Part {
  id: number
  name: string
  mpn: string | null
  sku: string | null
  manufacturer: string | null
  value: string | null
  status: 'active' | 'discontinued' | 'obsolete'
  total_quantity: number
  min_stock_threshold: number
  unit_price: number | null
  category: {
    id: number
    name: string
  } | null
  footprint: {
    id: number
    name: string
  } | null
}

interface PartsIndexProps {
  parts: Part[]
}

function getStatusBadgeVariant(status: string): 'default' | 'secondary' | 'destructive' | 'outline' {
  switch (status) {
    case 'active':
      return 'default'
    case 'discontinued':
      return 'secondary'
    case 'obsolete':
      return 'destructive'
    default:
      return 'outline'
  }
}

function getStockBadgeVariant(quantity: number, threshold: number): 'default' | 'secondary' | 'destructive' | 'outline' {
  if (quantity === 0) return 'destructive'
  if (quantity < threshold) return 'secondary'
  return 'outline'
}

function getStockLabel(quantity: number, threshold: number): string {
  if (quantity === 0) return 'Out of stock'
  if (quantity < threshold) return 'Low stock'
  return 'In stock'
}

export default function PartsIndex({ parts }: PartsIndexProps) {
  const breadcrumbs = [
    { label: 'Parts' },
  ]

  return (
    <AppLayout breadcrumbs={breadcrumbs}>
      <Head title="Parts" />

      <div className="space-y-4">
        <FlashMessages />

        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold tracking-tight">Parts</h1>
            <p className="text-muted-foreground">
              Manage your inventory parts
            </p>
          </div>
          <Button asChild>
            <Link href="/parts/new">
              <Plus className="mr-2 size-4" />
              Add Part
            </Link>
          </Button>
        </div>

        {/* Search and filters */}
        <div className="flex items-center gap-4">
          <div className="relative flex-1 max-w-sm">
            <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              placeholder="Search parts..."
              className="pl-9"
            />
          </div>
        </div>

        {/* Table */}
        {parts.length > 0 ? (
          <div className="rounded-md border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Name</TableHead>
                  <TableHead>MPN / SKU</TableHead>
                  <TableHead>Category</TableHead>
                  <TableHead>Footprint</TableHead>
                  <TableHead className="text-right">Quantity</TableHead>
                  <TableHead className="text-right">Unit Price</TableHead>
                  <TableHead>Stock Status</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="w-[80px]">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {parts.map((part) => (
                  <TableRow key={part.id}>
                    <TableCell>
                      <Link
                        href={`/parts/${part.id}`}
                        className="font-medium hover:underline"
                      >
                        {part.name}
                      </Link>
                      {part.manufacturer && (
                        <p className="text-sm text-muted-foreground">
                          {part.manufacturer}
                        </p>
                      )}
                    </TableCell>
                    <TableCell>
                      <div className="text-sm">
                        {part.mpn && <div>MPN: {part.mpn}</div>}
                        {part.sku && <div className="text-muted-foreground">SKU: {part.sku}</div>}
                        {!part.mpn && !part.sku && <span className="text-muted-foreground">-</span>}
                      </div>
                    </TableCell>
                    <TableCell>
                      {part.category?.name || <span className="text-muted-foreground">-</span>}
                    </TableCell>
                    <TableCell>
                      {part.footprint?.name || <span className="text-muted-foreground">-</span>}
                    </TableCell>
                    <TableCell className="text-right font-mono">
                      {part.total_quantity}
                    </TableCell>
                    <TableCell className="text-right font-mono">
                      {/* {part.unit_price != null
                        ? `$${part.unit_price.toFixed(2)}`
                        : <span className="text-muted-foreground">-</span>
                      } */}
                    </TableCell>
                    <TableCell>
                      <Badge variant={getStockBadgeVariant(part.total_quantity, part.min_stock_threshold)}>
                        {getStockLabel(part.total_quantity, part.min_stock_threshold)}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <Badge variant={getStatusBadgeVariant(part.status)}>
                        {part.status}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <Button variant="ghost" size="icon" asChild>
                        <Link href={`/parts/${part.id}/edit`}>
                          <Pencil className="size-4" />
                        </Link>
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        ) : (
          <div className="flex flex-col items-center justify-center rounded-lg border border-dashed p-12">
            <Package className="size-12 text-muted-foreground" />
            <h3 className="mt-4 text-lg font-semibold">No parts yet</h3>
            <p className="mt-2 text-sm text-muted-foreground">
              Get started by adding your first part.
            </p>
            <Button asChild className="mt-4">
              <Link href="/parts/new">
                <Plus className="mr-2 size-4" />
                Add Part
              </Link>
            </Button>
          </div>
        )}
      </div>
    </AppLayout>
  )
}
