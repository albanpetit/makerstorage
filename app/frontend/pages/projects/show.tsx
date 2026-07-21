import { Head, Link, router } from '@inertiajs/react'
import { useMemo, useState } from 'react'
import { ArrowLeft, CheckCircle2, AlertTriangle, XCircle, FileText, Hammer } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Combobox, type ComboboxOption } from '@/components/ui/combobox'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'

interface LinePart {
  id: number
  reference: string
  name: string
}

interface ProjectLine {
  id: number
  raw_reference: string | null
  designation: string | null
  quantity: number
  match_type: 'mpn' | 'sku' | 'name' | 'manual' | 'none'
  in_stock: number
  shortfall: number
  available: boolean
  part: LinePart | null
}

interface Project {
  id: number
  name: string
  reference: string | null
  status: 'draft' | 'confirmed'
  buildable: boolean
  short_count: number
  unmatched_count: number
  checked_at: string | null
  lines: ProjectLine[]
}

interface PartOption {
  id: number
  reference: string
  name: string
  mpn: string | null
  sku: string | null
}

interface ProjectShowProps {
  project: Project
  parts: PartOption[]
}

const NONE = '__none__'

const MATCH_LABELS: Record<ProjectLine['match_type'], string> = {
  mpn: 'by MPN',
  sku: 'by SKU',
  name: 'by name',
  manual: 'manual',
  none: 'no match',
}

export default function ProjectShow({ project, parts }: ProjectShowProps) {
  const { canWrite } = usePermissions()
  const [buildOpen, setBuildOpen] = useState(false)

  const partOptions = useMemo<ComboboxOption[]>(
    () => [
      { value: NONE, label: 'Not in inventory' },
      ...parts.map((p) => ({ value: String(p.id), label: `${p.reference} — ${p.name}` })),
    ],
    [parts]
  )

  const matchedCount = project.lines.filter((l) => l.part).length

  const updateLine = (line: ProjectLine, data: Record<string, string | number>) => {
    router.patch(`/projects/${project.id}/project_lines/${line.id}`, { project_line: data }, { preserveScroll: true })
  }

  const changePart = (line: ProjectLine, value: string) => {
    updateLine(line, { part_id: value === NONE ? '' : value })
  }

  const changeQuantity = (line: ProjectLine, raw: string) => {
    const quantity = Number(raw)
    if (!Number.isInteger(quantity) || quantity < 1 || quantity === line.quantity) return
    updateLine(line, { quantity })
  }

  return (
    <AppLayout
      header={
        <PageHeader title={project.name} subtitle={project.reference ?? undefined}>
          {canWrite && (
            <div className="flex gap-2">
              {project.status === 'draft' && (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => router.post(`/projects/${project.id}/confirm`, {}, { preserveScroll: true })}
                >
                  <CheckCircle2 className="size-4" />
                  Confirm matches
                </Button>
              )}
              <Button
                size="sm"
                variant="outline"
                disabled={project.short_count === 0}
                title={project.short_count === 0 ? 'No shortfalls to order' : undefined}
                onClick={() => router.post(`/projects/${project.id}/create_purchase_orders`, {}, { preserveScroll: true })}
              >
                <FileText className="size-4" />
                Order shortfalls
              </Button>
              <Button
                size="sm"
                disabled={!project.buildable}
                title={project.buildable ? undefined : 'Resolve shortfalls and unmatched lines first'}
                onClick={() => setBuildOpen(true)}
              >
                <Hammer className="size-4" />
                Build kit
              </Button>
            </div>
          )}
        </PageHeader>
      }
    >
      <Head title={project.name} />

      <div className="space-y-6">
        <FlashMessages />

        <Link href="/projects" className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground">
          <ArrowLeft className="size-4" />
          All projects
        </Link>

        {/* Availability summary */}
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <SummaryCard label="Total lines" value={project.lines.length} />
          <SummaryCard label="Matched" value={`${matchedCount} / ${project.lines.length}`} />
          <SummaryCard label="Short on stock" value={project.short_count} tone={project.short_count > 0 ? 'amber' : undefined} />
          <SummaryCard label="Not in inventory" value={project.unmatched_count} tone={project.unmatched_count > 0 ? 'red' : undefined} />
        </div>

        <Card className={`border-l-[3px] ${project.buildable ? 'border-l-emerald-500' : 'border-l-amber-500'}`}>
          <CardContent className="flex items-center gap-3">
            {project.buildable ? (
              <>
                <CheckCircle2 className="size-5 text-emerald-600 dark:text-emerald-400" />
                <p className="text-sm font-medium">You have enough stock to build this project.</p>
              </>
            ) : (
              <>
                <AlertTriangle className="size-5 text-amber-600 dark:text-amber-400" />
                <p className="text-sm font-medium">
                  {project.short_count + project.unmatched_count} line{project.short_count + project.unmatched_count !== 1 ? 's' : ''} need resolving before this project is buildable.
                </p>
              </>
            )}
          </CardContent>
        </Card>

        {/* BOM lines */}
        <Card className="overflow-hidden py-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>BOM reference</TableHead>
                <TableHead>Matched part</TableHead>
                <TableHead className="text-right">Required</TableHead>
                <TableHead className="text-right">In stock</TableHead>
                <TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {project.lines.map((line) => (
                <TableRow key={line.id}>
                  <TableCell>
                    <div className="font-mono text-sm font-medium">{line.raw_reference || '—'}</div>
                    <div className="max-w-[220px] truncate text-xs text-muted-foreground">{line.designation}</div>
                  </TableCell>
                  <TableCell>
                    {canWrite ? (
                      <div className="flex items-center gap-2">
                        <Combobox
                          options={partOptions}
                          value={line.part ? String(line.part.id) : NONE}
                          onValueChange={(value) => changePart(line, value)}
                          placeholder="Not in inventory"
                          searchPlaceholder="Search parts…"
                          className="min-w-[220px]"
                        />
                        <span className="text-xs text-muted-foreground">{MATCH_LABELS[line.match_type]}</span>
                      </div>
                    ) : line.part ? (
                      <span>{line.part.reference} — {line.part.name}</span>
                    ) : (
                      <span className="text-muted-foreground">Not in inventory</span>
                    )}
                  </TableCell>
                  <TableCell className="text-right">
                    {canWrite ? (
                      <Input
                        type="number"
                        min={1}
                        defaultValue={line.quantity}
                        className="ml-auto h-8 w-20 text-right font-mono"
                        onBlur={(e) => changeQuantity(line, e.target.value)}
                      />
                    ) : (
                      <span className="font-mono">{line.quantity}</span>
                    )}
                  </TableCell>
                  <TableCell className="text-right font-mono">{line.part ? line.in_stock : '—'}</TableCell>
                  <TableCell>
                    {!line.part ? (
                      <Badge variant="outline" className="bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-400">
                        <XCircle className="size-3.5" /> Not in inventory
                      </Badge>
                    ) : line.available ? (
                      <Badge variant="outline" className="bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400">
                        <CheckCircle2 className="size-3.5" /> OK
                      </Badge>
                    ) : (
                      <Badge variant="outline" className="bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400">
                        <AlertTriangle className="size-3.5" /> Short {line.shortfall}
                      </Badge>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Card>
      </div>

      {/* Build confirmation */}
      <AlertDialog open={buildOpen} onOpenChange={setBuildOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Build this kit?</AlertDialogTitle>
            <AlertDialogDescription>
              This deducts the required quantity of every matched part from stock, recording an outgoing movement for each. This can't be undone automatically.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                router.post(`/projects/${project.id}/build`, {}, { preserveScroll: true })
                setBuildOpen(false)
              }}
            >
              Deduct stock
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </AppLayout>
  )
}

function SummaryCard({ label, value, tone }: { label: string; value: string | number; tone?: 'amber' | 'red' }) {
  const toneClass = tone === 'amber' ? 'text-amber-600 dark:text-amber-400' : tone === 'red' ? 'text-red-600 dark:text-red-400' : ''
  return (
    <Card>
      <CardContent>
        <div className="text-sm text-muted-foreground">{label}</div>
        <div className={`mt-1 font-mono text-2xl font-bold ${toneClass}`}>{value}</div>
      </CardContent>
    </Card>
  )
}
