import { Head, Link, router } from '@inertiajs/react'
import { FormEvent, useMemo, useRef, useState } from 'react'
import { ArrowLeft, CheckCircle2, AlertTriangle, XCircle, FileText, Hammer, Lock, LockOpen, Download, FileCode2, RefreshCw, Trash2, Upload, GitBranch, ExternalLink, Pencil, Unlink } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { KICAD_ACCEPT, formatFileSize } from '@/lib/kicad-files'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardAction } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Combobox, type ComboboxOption } from '@/components/ui/combobox'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { GithubFields, type GithubLinkData } from '@/components/projects/github-fields'
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
  value: string | null
  footprint: string | null
  designators: string | null
  quantity: number
  match_type: 'mpn' | 'sku' | 'supplier_sku' | 'value_footprint' | 'name' | 'manual' | 'none'
  in_stock: number
  reserved_elsewhere: number
  shortfall: number
  available: boolean
  part: LinePart | null
}

interface ProjectFile {
  id: number
  filename: string
  byte_size: number
  created_at: string
  url: string
  from_github: boolean
}

interface GithubLink {
  repository: string
  ref: string | null
  path: string | null
  location: string
  url: string
  synced_sha: string | null
  synced_at: string | null
  commit_url: string | null
}

interface Project {
  id: number
  name: string
  reference: string | null
  status: 'draft' | 'confirmed'
  reservations_enabled: boolean
  reserved: boolean
  reserved_at: string | null
  buildable: boolean
  short_count: number
  unmatched_count: number
  checked_at: string | null
  builds_count: number
  last_built_at: string | null
  lines: ProjectLine[]
  files: ProjectFile[]
  files_have_schematics: boolean
  github: GithubLink | null
  github_token_configured: boolean
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
  supplier_sku: 'by supplier SKU',
  value_footprint: 'by value + footprint',
  name: 'by name',
  manual: 'manual',
  none: 'no match',
}

export default function ProjectShow({ project, parts }: ProjectShowProps) {
  const { canWrite } = usePermissions()
  const [buildOpen, setBuildOpen] = useState(false)
  const [importOpen, setImportOpen] = useState(false)
  const [removeFile, setRemoveFile] = useState<ProjectFile | null>(null)
  const [uploading, setUploading] = useState(false)
  const fileInput = useRef<HTMLInputElement>(null)
  const [githubOpen, setGithubOpen] = useState(false)
  const [unlinkOpen, setUnlinkOpen] = useState(false)
  const [syncing, setSyncing] = useState(false)
  const [githubData, setGithubData] = useState<GithubLinkData>({ repository: '', ref: '', path: '' })

  const openGithubDialog = () => {
    setGithubData({
      repository: project.github?.repository ?? '',
      ref: project.github?.ref ?? '',
      path: project.github?.path ?? '',
    })
    setGithubOpen(true)
  }

  const saveGithubLink = (e: FormEvent) => {
    e.preventDefault()
    setSyncing(true)
    router.patch(`/projects/${project.id}/github`, { ...githubData }, {
      preserveScroll: true,
      onSuccess: () => setGithubOpen(false),
      onFinish: () => setSyncing(false),
    })
  }

  const syncGithub = () => {
    setSyncing(true)
    router.post(`/projects/${project.id}/github/sync`, {}, { preserveScroll: true, onFinish: () => setSyncing(false) })
  }

  const uploadFiles = (files: FileList | null) => {
    if (!files || files.length === 0) return
    const formData = new FormData()
    Array.from(files).forEach((file) => formData.append('files[]', file))
    setUploading(true)
    router.post(`/projects/${project.id}/files`, formData, {
      preserveScroll: true,
      onFinish: () => {
        setUploading(false)
        if (fileInput.current) fileInput.current.value = ''
      },
    })
  }

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
              {project.status === 'confirmed' && project.reservations_enabled && (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => router.post(`/projects/${project.id}/${project.reserved ? 'release' : 'reserve'}`, {}, { preserveScroll: true })}
                >
                  {project.reserved ? <LockOpen className="size-4" /> : <Lock className="size-4" />}
                  {project.reserved ? 'Release stock' : 'Reserve stock'}
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
            {project.reserved && project.reserved_at && (
              <Badge variant="outline" className="ml-auto">
                <Lock className="size-3.5" /> Stock reserved since {new Date(project.reserved_at).toLocaleDateString()}
              </Badge>
            )}
            {project.builds_count > 0 && project.last_built_at && (
              <p className={`${project.reserved ? '' : 'ml-auto '}text-xs text-muted-foreground`}>
                Built {project.builds_count} time{project.builds_count !== 1 ? 's' : ''} · last on {new Date(project.last_built_at).toLocaleDateString()}
              </p>
            )}
          </CardContent>
        </Card>

        {/* KiCad files */}
        <Card>
          <CardHeader>
            <CardTitle>KiCad files</CardTitle>
            <CardDescription>
              The project's design files, a ZIP of its folder, or the files of a linked GitHub repository. The BOM can be read again from the schematics after a design change.
            </CardDescription>
            {canWrite && (
              <CardAction className="flex gap-2">
                {project.files_have_schematics && (
                  <Button size="sm" variant="outline" onClick={() => setImportOpen(true)}>
                    <RefreshCw className="size-4" />
                    Update BOM from schematic
                  </Button>
                )}
                {!project.github && (
                  <Button size="sm" variant="outline" onClick={openGithubDialog}>
                    <GitBranch className="size-4" />
                    Link to GitHub
                  </Button>
                )}
                <Button size="sm" variant="outline" disabled={uploading} onClick={() => fileInput.current?.click()}>
                  <Upload className="size-4" />
                  Add files
                </Button>
                <Input
                  ref={fileInput}
                  type="file"
                  multiple
                  accept={KICAD_ACCEPT}
                  className="hidden"
                  aria-label="KiCad files"
                  onChange={(e) => uploadFiles(e.target.files)}
                />
              </CardAction>
            )}
          </CardHeader>
          <CardContent className="space-y-3">
            {project.github && (
              <div className="flex flex-wrap items-center gap-x-3 gap-y-2 rounded-md border bg-muted/40 px-3 py-2 text-sm">
                <GitBranch className="size-4 shrink-0 text-muted-foreground" />
                <a
                  href={project.github.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex min-w-0 items-center gap-1 font-mono font-medium hover:underline"
                >
                  <span className="truncate">{project.github.location}</span>
                  <ExternalLink className="size-3.5 shrink-0 text-muted-foreground" />
                </a>
                <span className="text-xs text-muted-foreground">
                  {project.github.synced_sha && project.github.commit_url ? (
                    <>
                      Commit{' '}
                      <a href={project.github.commit_url} target="_blank" rel="noopener noreferrer" className="font-mono hover:underline">
                        {project.github.synced_sha.slice(0, 7)}
                      </a>
                      {project.github.synced_at && <> · checked {new Date(project.github.synced_at).toLocaleString()}</>}
                    </>
                  ) : (
                    'Not fetched yet'
                  )}
                </span>
                {canWrite && (
                  <div className="ml-auto flex gap-1">
                    <Button size="sm" onClick={syncGithub} disabled={syncing}>
                      <RefreshCw className={`size-4 ${syncing ? 'animate-spin' : ''}`} />
                      Update from GitHub
                    </Button>
                    <Button size="icon-sm" variant="ghost" aria-label="Edit GitHub link" onClick={openGithubDialog}>
                      <Pencil className="size-4 text-muted-foreground" />
                    </Button>
                    <Button size="icon-sm" variant="ghost" aria-label="Unlink from GitHub" onClick={() => setUnlinkOpen(true)}>
                      <Unlink className="size-4 text-muted-foreground" />
                    </Button>
                  </div>
                )}
              </div>
            )}
            {project.files.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                No files yet.{canWrite && ' Add the .kicad_pro, .kicad_sch and .kicad_pcb files, a ZIP of the project folder, or link a GitHub repository.'}
              </p>
            ) : (
              <ul className="grid gap-x-8 lg:grid-cols-2">
                {project.files.map((file) => (
                  <li key={file.id} className="flex items-center gap-3 border-b py-1.5">
                    <FileCode2 className="size-4 shrink-0 text-muted-foreground" />
                    <a
                      href={`${file.url}?disposition=attachment`}
                      className="inline-flex min-w-0 items-center gap-1.5 font-mono text-sm hover:underline"
                      title={`Download ${file.filename}`}
                      download
                    >
                      <span className="truncate">{file.filename}</span>
                      <Download className="size-3.5 shrink-0 text-muted-foreground" />
                    </a>
                    {file.from_github && (
                      <Badge variant="outline" className="shrink-0" title="Fetched from GitHub: replaced on the next update">
                        GitHub
                      </Badge>
                    )}
                    <span className="ml-auto shrink-0 text-xs text-muted-foreground">
                      {formatFileSize(file.byte_size)} · {new Date(file.created_at).toLocaleDateString()}
                    </span>
                    {canWrite && (
                      <Button variant="ghost" size="icon-sm" aria-label={`Remove ${file.filename}`} onClick={() => setRemoveFile(file)}>
                        <Trash2 className="size-4 text-muted-foreground" />
                      </Button>
                    )}
                  </li>
                ))}
              </ul>
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
                {project.reservations_enabled && (
                  <TableHead className="text-right" title="Held by projects reserved before this one">Reserved elsewhere</TableHead>
                )}
                <TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {project.lines.map((line) => (
                <TableRow key={line.id}>
                  <TableCell>
                    <div className="font-mono text-sm font-medium">{line.raw_reference || '—'}</div>
                    <div className="max-w-[220px] truncate text-xs text-muted-foreground">{line.designation}</div>
                    {(line.footprint || (line.value && line.value !== line.designation)) && (
                      <div className="max-w-[220px] truncate text-xs text-muted-foreground" title={line.footprint ?? undefined}>
                        {[line.value !== line.designation ? line.value : null, line.footprint?.split(':').pop()]
                          .filter(Boolean)
                          .join(' · ')}
                      </div>
                    )}
                    {line.designators && (
                      <div className="max-w-[220px] truncate font-mono text-xs text-muted-foreground" title={line.designators}>
                        {line.designators}
                      </div>
                    )}
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
                  {project.reservations_enabled && (
                    <TableCell className="text-right font-mono text-muted-foreground">
                      {line.part && line.reserved_elsewhere > 0 ? line.reserved_elsewhere : '—'}
                    </TableCell>
                  )}
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

      {/* Update BOM confirmation */}
      <AlertDialog open={importOpen} onOpenChange={setImportOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Update the BOM from the schematic?</AlertDialogTitle>
            <AlertDialogDescription>
              The BOM lines are replaced by the components of the attached schematics and matched again. Parts you picked by hand stay on the components that are still there. The project goes back to draft{project.reserved && ' and its stock reservation is released'}.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                router.post(`/projects/${project.id}/files/import_bom`, {}, { preserveScroll: true })
                setImportOpen(false)
              }}
            >
              Update BOM
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* GitHub link */}
      <Dialog open={githubOpen} onOpenChange={setGithubOpen}>
        <DialogContent className="sm:max-w-md">
          <form onSubmit={saveGithubLink}>
            <DialogHeader>
              <DialogTitle>{project.github ? 'Edit the GitHub link' : 'Link to a GitHub repository'}</DialogTitle>
              <DialogDescription>
                The KiCad files in the repository (or in one folder of it) are fetched into this project and its BOM is read from the schematics. Use “Update from GitHub” after pushing a change.
              </DialogDescription>
            </DialogHeader>
            <div className="py-4">
              <GithubFields data={githubData} onChange={setGithubData} tokenConfigured={project.github_token_configured} autoFocus />
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setGithubOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={syncing || !githubData.repository.trim()}>
                <GitBranch className="size-4" />
                {project.github ? 'Save & fetch' : 'Link & fetch'}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Unlink confirmation */}
      <AlertDialog open={unlinkOpen} onOpenChange={setUnlinkOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Unlink from GitHub?</AlertDialogTitle>
            <AlertDialogDescription>
              The project stops following {project.github?.location}. The files fetched so far and the BOM stay as they are.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                router.delete(`/projects/${project.id}/github`, { preserveScroll: true })
                setUnlinkOpen(false)
              }}
            >
              Unlink
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Remove file confirmation */}
      <AlertDialog open={removeFile !== null} onOpenChange={(o) => !o && setRemoveFile(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove {removeFile?.filename}?</AlertDialogTitle>
            <AlertDialogDescription>The file is deleted. The BOM lines already imported stay as they are.</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (removeFile) router.delete(`/projects/${project.id}/files/${removeFile.id}`, { preserveScroll: true })
                setRemoveFile(null)
              }}
            >
              Remove
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Build confirmation */}
      <AlertDialog open={buildOpen} onOpenChange={setBuildOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Build this kit?</AlertDialogTitle>
            <AlertDialogDescription>
              This deducts the required quantity of every matched part from stock, recording an outgoing movement for each. This can't be undone automatically.
              {project.reserved && ' The project\'s stock reservation is released once the kit is built.'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                router.post(`/projects/${project.id}/build`, { builds_count: project.builds_count }, { preserveScroll: true })
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
