import { Head, Link, router } from '@inertiajs/react'
import { FormEvent, useMemo, useRef, useState } from 'react'
import {
  ArrowLeft,
  CheckCircle2,
  AlertTriangle,
  XCircle,
  FileText,
  Hammer,
  Lock,
  LockOpen,
  Plus,
  Pencil,
  Copy,
  Trash2,
  History,
  Download,
  FileCode2,
  RefreshCw,
  Upload,
  GitBranch,
  ExternalLink,
  Unlink,
} from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { KICAD_ACCEPT, formatFileSize } from '@/lib/kicad-files'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardAction } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Combobox, type ComboboxOption } from '@/components/ui/combobox'
import { GithubFields, type GithubLinkData } from '@/components/projects/github-fields'
import { ProjectCostCard, type ProjectCostData } from '@/components/projects/project-cost-card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
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
import { t, tn, intlLocale } from '@/lib/i18n'

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

interface ProjectBuild {
  id: number
  quantity: number
  built_at: string
  note: string | null
  user: string | null
  references: number
  units: number
}

interface Project {
  id: number
  name: string
  description: string | null
  reference: string | null
  revision: string | null
  next_revision: string
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
  builds: ProjectBuild[]
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
  cost: ProjectCostData
}

const NONE = '__none__'

const MATCH_LABELS: Record<ProjectLine['match_type'], string> = {
  get mpn() { return t('by MPN') },
  get sku() { return t('by SKU') },
  get supplier_sku() { return t('by supplier SKU') },
  get value_footprint() { return t('by value + footprint') },
  get name() { return t('by name') },
  get manual() { return t('manual') },
  get none() { return t('no match') },
}

export default function ProjectShow({ project, parts, cost }: ProjectShowProps) {
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
  const [kits, setKits] = useState('1')
  const [buildNote, setBuildNote] = useState('')
  const [editOpen, setEditOpen] = useState(false)
  const [revisionOpen, setRevisionOpen] = useState(false)
  const [lineOpen, setLineOpen] = useState(false)
  const [removeLine, setRemoveLine] = useState<ProjectLine | null>(null)

  const partOptions = useMemo<ComboboxOption[]>(
    () => [
      { value: NONE, label: t('Not in inventory') },
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

  const kitCount = Number(kits)
  const kitsValid = Number.isInteger(kitCount) && kitCount >= 1

  const build = () => {
    router.post(
      `/projects/${project.id}/build`,
      { builds_count: project.builds_count, kits: kitCount, note: buildNote.trim() },
      { preserveScroll: true, onSuccess: () => { setKits('1'); setBuildNote('') } }
    )
    setBuildOpen(false)
  }

  const subtitle = [project.reference, project.revision ? `rev ${project.revision}` : null].filter(Boolean).join(' · ')

  return (
    <AppLayout
      header={
        <PageHeader title={project.name} subtitle={subtitle || undefined}>
          {canWrite && (
            <div className="flex flex-wrap gap-2">
              <Button size="sm" variant="outline" onClick={() => setEditOpen(true)}>
                <Pencil className="size-4" />
                {t('Edit')}
              </Button>
              <Button size="sm" variant="outline" onClick={() => setRevisionOpen(true)}>
                <Copy className="size-4" />
                {t('New revision')}
              </Button>
              {project.status === 'draft' && (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => router.post(`/projects/${project.id}/confirm`, {}, { preserveScroll: true })}
                >
                  <CheckCircle2 className="size-4" />
                  {t('Confirm matches')}
                </Button>
              )}
              {project.status === 'confirmed' && project.reservations_enabled && (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => router.post(`/projects/${project.id}/${project.reserved ? 'release' : 'reserve'}`, {}, { preserveScroll: true })}
                >
                  {project.reserved ? <LockOpen className="size-4" /> : <Lock className="size-4" />}
                  {project.reserved ? t('Release stock') : t('Reserve stock')}
                </Button>
              )}
              <Button
                size="sm"
                variant="outline"
                disabled={project.short_count === 0}
                title={project.short_count === 0 ? t('No shortfalls to order') : undefined}
                onClick={() => router.post(`/projects/${project.id}/create_purchase_orders`, {}, { preserveScroll: true })}
              >
                <FileText className="size-4" />
                {t('Order shortfalls')}
              </Button>
              <Button
                size="sm"
                disabled={!project.buildable}
                title={project.buildable ? undefined : t('Resolve shortfalls and unmatched lines first')}
                onClick={() => setBuildOpen(true)}
              >
                <Hammer className="size-4" />
                {t('Build')}
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
          {t('All projects')}
        </Link>

        {project.description && <p className="max-w-3xl text-sm text-muted-foreground">{project.description}</p>}

        {/* Availability summary */}
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <SummaryCard label={t('Total lines')} value={project.lines.length} />
          <SummaryCard label={t('Matched')} value={`${matchedCount} / ${project.lines.length}`} />
          <SummaryCard label={t('Short on stock')} value={project.short_count} tone={project.short_count > 0 ? 'amber' : undefined} />
          <SummaryCard label={t('Not in inventory')} value={project.unmatched_count} tone={project.unmatched_count > 0 ? 'red' : undefined} />
        </div>

        <Card className={`border-l-[3px] ${project.buildable ? 'border-l-emerald-500' : 'border-l-amber-500'}`}>
          <CardContent className="flex items-center gap-3">
            {project.buildable ? (
              <>
                <CheckCircle2 className="size-5 text-emerald-600 dark:text-emerald-400" />
                <p className="text-sm font-medium">{t('You have enough stock to build this project.')}</p>
              </>
            ) : project.lines.length === 0 ? (
              <>
                <AlertTriangle className="size-5 text-amber-600 dark:text-amber-400" />
                <p className="text-sm font-medium">{t('This project has no lines yet: add the parts it needs to see what you can build.')}</p>
              </>
            ) : (
              <>
                <AlertTriangle className="size-5 text-amber-600 dark:text-amber-400" />
                <p className="text-sm font-medium">
                  {tn(
                    '{count} line needs resolving before this project is buildable.',
                    '{count} lines need resolving before this project is buildable.',
                    project.short_count + project.unmatched_count,
                  )}
                </p>
              </>
            )}
            {project.reserved && project.reserved_at && (
              <Badge variant="outline" className="ml-auto">
                <Lock className="size-3.5" /> {t('Stock reserved since {date}', { date: new Date(project.reserved_at).toLocaleDateString(intlLocale()) })}
              </Badge>
            )}
            {project.builds_count > 0 && project.last_built_at && (
              <p className={`${project.reserved ? '' : 'ml-auto '}text-xs text-muted-foreground`}>
                {tn('{count} kit built · last on {date}', '{count} kits built · last on {date}', project.builds_count, { date: new Date(project.last_built_at).toLocaleDateString(intlLocale()) })}
              </p>
            )}
          </CardContent>
        </Card>

        {/* KiCad files */}
        <Card>
          <CardHeader>
            <CardTitle>{t('KiCad files')}</CardTitle>
            <CardDescription>
              {t('The project\'s design files, a ZIP of its folder, or the files of a linked GitHub repository. The BOM can be read again from the schematics after a design change.')}
            </CardDescription>
            {canWrite && (
              <CardAction className="flex gap-2">
                {project.files_have_schematics && (
                  <Button size="sm" variant="outline" onClick={() => setImportOpen(true)}>
                    <RefreshCw className="size-4" />
                    {t('Update BOM from schematic')}
                  </Button>
                )}
                {!project.github && (
                  <Button size="sm" variant="outline" onClick={openGithubDialog}>
                    <GitBranch className="size-4" />
                    {t('Link to GitHub')}
                  </Button>
                )}
                <Button size="sm" variant="outline" disabled={uploading} onClick={() => fileInput.current?.click()}>
                  <Upload className="size-4" />
                  {t('Add files')}
                </Button>
                <Input
                  ref={fileInput}
                  type="file"
                  multiple
                  accept={KICAD_ACCEPT}
                  className="hidden"
                  aria-label={t('KiCad files')}
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
                      {t('Commit')}{' '}
                      <a href={project.github.commit_url} target="_blank" rel="noopener noreferrer" className="font-mono hover:underline">
                        {project.github.synced_sha.slice(0, 7)}
                      </a>
                      {project.github.synced_at && <> · {t('checked {date}', { date: new Date(project.github.synced_at).toLocaleString(intlLocale()) })}</>}
                    </>
                  ) : (
                    t('Not fetched yet')
                  )}
                </span>
                {canWrite && (
                  <div className="ml-auto flex gap-1">
                    <Button size="sm" onClick={syncGithub} disabled={syncing}>
                      <RefreshCw className={`size-4 ${syncing ? 'animate-spin' : ''}`} />
                      {t('Update from GitHub')}
                    </Button>
                    <Button size="icon-sm" variant="ghost" aria-label={t('Edit GitHub link')} onClick={openGithubDialog}>
                      <Pencil className="size-4 text-muted-foreground" />
                    </Button>
                    <Button size="icon-sm" variant="ghost" aria-label={t('Unlink from GitHub')} onClick={() => setUnlinkOpen(true)}>
                      <Unlink className="size-4 text-muted-foreground" />
                    </Button>
                  </div>
                )}
              </div>
            )}
            {project.files.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                {t('No files yet.')}{canWrite && ` ${t('Add the .kicad_pro, .kicad_sch and .kicad_pcb files, a ZIP of the project folder, or link a GitHub repository.')}`}
              </p>
            ) : (
              <ul className="grid gap-x-8 lg:grid-cols-2">
                {project.files.map((file) => (
                  <li key={file.id} className="flex items-center gap-3 border-b py-1.5">
                    <FileCode2 className="size-4 shrink-0 text-muted-foreground" />
                    <a
                      href={`${file.url}?disposition=attachment`}
                      className="inline-flex min-w-0 items-center gap-1.5 font-mono text-sm hover:underline"
                      title={t('Download {name}', { name: file.filename })}
                      download
                    >
                      <span className="truncate">{file.filename}</span>
                      <Download className="size-3.5 shrink-0 text-muted-foreground" />
                    </a>
                    {file.from_github && (
                      <Badge variant="outline" className="shrink-0" title={t('Fetched from GitHub: replaced on the next update')}>
                        GitHub
                      </Badge>
                    )}
                    <span className="ml-auto shrink-0 text-xs text-muted-foreground">
                      {formatFileSize(file.byte_size)} · {new Date(file.created_at).toLocaleDateString(intlLocale())}
                    </span>
                    {canWrite && (
                      <Button variant="ghost" size="icon-sm" aria-label={t('Remove {name}', { name: file.filename })} onClick={() => setRemoveFile(file)}>
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
                <TableHead>{t('BOM reference')}</TableHead>
                <TableHead>{t('Matched part')}</TableHead>
                <TableHead className="text-right">{t('Required')}</TableHead>
                <TableHead className="text-right">{t('In stock')}</TableHead>
                {project.reservations_enabled && (
                  <TableHead className="text-right" title={t('Held by projects reserved before this one')}>{t('Reserved elsewhere')}</TableHead>
                )}
                <TableHead>{t('Status')}</TableHead>
                {canWrite && <TableHead className="w-10" />}
              </TableRow>
            </TableHeader>
            <TableBody>
              {project.lines.length === 0 && (
                <TableRow>
                  <TableCell colSpan={7} className="py-8 text-center text-sm text-muted-foreground">
                    No lines yet.{canWrite && ' Add the parts this project needs.'}
                  </TableCell>
                </TableRow>
              )}
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
                          placeholder={t('Not in inventory')}
                          searchPlaceholder={t('Search parts…')}
                          className="min-w-[220px]"
                        />
                        <span className="text-xs text-muted-foreground">{MATCH_LABELS[line.match_type]}</span>
                      </div>
                    ) : line.part ? (
                      <span>{line.part.reference} — {line.part.name}</span>
                    ) : (
                      <span className="text-muted-foreground">{t('Not in inventory')}</span>
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
                        <XCircle className="size-3.5" /> {t('Not in inventory')}
                      </Badge>
                    ) : line.available ? (
                      <Badge variant="outline" className="bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400">
                        <CheckCircle2 className="size-3.5" /> {t('OK')}
                      </Badge>
                    ) : (
                      <Badge variant="outline" className="bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400">
                        <AlertTriangle className="size-3.5" /> {t('Short {count}', { count: line.shortfall })}
                      </Badge>
                    )}
                  </TableCell>
                  {canWrite && (
                    <TableCell>
                      <Button variant="ghost" size="icon-sm" aria-label={t('Remove line')} onClick={() => setRemoveLine(line)}>
                        <Trash2 className="size-4 text-muted-foreground" />
                      </Button>
                    </TableCell>
                  )}
                </TableRow>
              ))}
            </TableBody>
          </Table>
          {canWrite && (
            <div className="border-t px-4 py-3">
              <Button size="sm" variant="outline" onClick={() => setLineOpen(true)}>
                <Plus className="size-4" />
                {t('Add line')}
              </Button>
            </div>
          )}
        </Card>

        <ProjectCostCard projectId={project.id} cost={cost} />

        <BuildHistory builds={project.builds} />
      </div>

      <EditProjectDialog project={project} open={editOpen} onOpenChange={setEditOpen} />
      <NewRevisionDialog project={project} open={revisionOpen} onOpenChange={setRevisionOpen} />
      <AddLineDialog projectId={project.id} partOptions={partOptions} open={lineOpen} onOpenChange={setLineOpen} />

      {/* Update BOM confirmation */}
      <AlertDialog open={importOpen} onOpenChange={setImportOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('Update the BOM from the schematic?')}</AlertDialogTitle>
            <AlertDialogDescription>
              {project.reserved
                ? t('The BOM lines are replaced by the components of the attached schematics and matched again. Parts you picked by hand stay on the components that are still there. The project goes back to draft and its stock reservation is released.')
                : t('The BOM lines are replaced by the components of the attached schematics and matched again. Parts you picked by hand stay on the components that are still there. The project goes back to draft.')}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('Cancel')}</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                router.post(`/projects/${project.id}/files/import_bom`, {}, { preserveScroll: true })
                setImportOpen(false)
              }}
            >
              {t('Update BOM')}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* GitHub link */}
      <Dialog open={githubOpen} onOpenChange={setGithubOpen}>
        <DialogContent className="sm:max-w-md">
          <form onSubmit={saveGithubLink}>
            <DialogHeader>
              <DialogTitle>{project.github ? t('Edit the GitHub link') : t('Link to a GitHub repository')}</DialogTitle>
              <DialogDescription>
                {t('The KiCad files in the repository (or in one folder of it) are fetched into this project and its BOM is read from the schematics. Use “Update from GitHub” after pushing a change.')}
              </DialogDescription>
            </DialogHeader>
            <div className="py-4">
              <GithubFields data={githubData} onChange={setGithubData} tokenConfigured={project.github_token_configured} autoFocus />
            </div>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setGithubOpen(false)}>
                {t('Cancel')}
              </Button>
              <Button type="submit" disabled={syncing || !githubData.repository.trim()}>
                <GitBranch className="size-4" />
                {project.github ? t('Save & fetch') : t('Link & fetch')}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Unlink confirmation */}
      <AlertDialog open={unlinkOpen} onOpenChange={setUnlinkOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('Unlink from GitHub?')}</AlertDialogTitle>
            <AlertDialogDescription>
              {t('The project stops following {location}. The files fetched so far and the BOM stay as they are.', { location: project.github?.location ?? '' })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('Cancel')}</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                router.delete(`/projects/${project.id}/github`, { preserveScroll: true })
                setUnlinkOpen(false)
              }}
            >
              {t('Unlink')}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Remove file confirmation */}
      <AlertDialog open={removeFile !== null} onOpenChange={(o) => !o && setRemoveFile(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('Remove {name}?', { name: removeFile?.filename ?? '' })}</AlertDialogTitle>
            <AlertDialogDescription>{t('The file is deleted. The BOM lines already imported stay as they are.')}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('Cancel')}</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (removeFile) router.delete(`/projects/${project.id}/files/${removeFile.id}`, { preserveScroll: true })
                setRemoveFile(null)
              }}
            >
              {t('Remove')}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Remove line confirmation */}
      <AlertDialog open={removeLine !== null} onOpenChange={(o) => !o && setRemoveLine(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('Remove this line?')}</AlertDialogTitle>
            <AlertDialogDescription>
              {t('{line} is removed from the project. Stock is not affected.', { line: removeLine?.designation || removeLine?.raw_reference || t('This line') })}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('Cancel')}</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (removeLine) router.delete(`/projects/${project.id}/project_lines/${removeLine.id}`, { preserveScroll: true })
                setRemoveLine(null)
              }}
            >
              {t('Remove')}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Build confirmation */}
      <AlertDialog open={buildOpen} onOpenChange={setBuildOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('Build this project?')}</AlertDialogTitle>
            <AlertDialogDescription>
              {t('This deducts the required quantity of every matched part from stock, times the number of kits, recording an outgoing movement for each and an entry in the build history. This can\'t be undone automatically.')}
              {project.reserved && ` ${t('The project\'s stock reservation is released once built.')}`}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <div className="grid gap-4 sm:grid-cols-[120px_1fr]">
            <div className="space-y-2">
              <Label htmlFor="build-kits">{t('Kits')}</Label>
              <Input id="build-kits" type="number" min={1} value={kits} onChange={(e) => setKits(e.target.value)} className="font-mono" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="build-note">{t('Note')}</Label>
              <Input
                id="build-note"
                value={buildNote}
                maxLength={255}
                onChange={(e) => setBuildNote(e.target.value)}
                placeholder={t('Optional, e.g. workshop of 12 October')}
              />
            </div>
          </div>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('Cancel')}</AlertDialogCancel>
            <AlertDialogAction disabled={!kitsValid} onClick={build}>
              {t('Deduct stock')}
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

function BuildHistory({ builds }: { builds: ProjectBuild[] }) {
  if (builds.length === 0) return null

  return (
    <Card className="overflow-hidden py-0">
      <div className="flex items-center gap-2 border-b px-4 py-3">
        <History className="size-4 text-muted-foreground" />
        <h2 className="text-sm font-semibold">{t('Build history')}</h2>
      </div>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{t('Date')}</TableHead>
            <TableHead className="text-right">{t('Kits')}</TableHead>
            <TableHead className="text-right">{t('Parts taken')}</TableHead>
            <TableHead>{t('By')}</TableHead>
            <TableHead>{t('Note')}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {builds.map((build) => (
            <TableRow key={build.id}>
              <TableCell className="text-sm">{new Date(build.built_at).toLocaleString(intlLocale())}</TableCell>
              <TableCell className="text-right font-mono">{build.quantity}</TableCell>
              <TableCell className="text-right font-mono text-muted-foreground">
                {build.units} ({tn('{count} ref', '{count} refs', build.references)})
              </TableCell>
              <TableCell className="text-sm">{build.user ?? '—'}</TableCell>
              <TableCell className="max-w-[320px] truncate text-sm text-muted-foreground" title={build.note ?? undefined}>
                {build.note ?? ''}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </Card>
  )
}

interface DialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

function EditProjectDialog({ project, open, onOpenChange }: DialogProps & { project: Project }) {
  const [name, setName] = useState(project.name)
  const [revision, setRevision] = useState(project.revision ?? '')
  const [description, setDescription] = useState(project.description ?? '')
  const [processing, setProcessing] = useState(false)

  const openChange = (next: boolean) => {
    if (next) {
      setName(project.name)
      setRevision(project.revision ?? '')
      setDescription(project.description ?? '')
    }
    onOpenChange(next)
  }

  const submit = (e: FormEvent) => {
    e.preventDefault()
    setProcessing(true)
    router.patch(
      `/projects/${project.id}`,
      { project: { name: name.trim(), revision: revision.trim(), description: description.trim() } },
      { preserveScroll: true, onSuccess: () => onOpenChange(false), onFinish: () => setProcessing(false) }
    )
  }

  return (
    <Dialog open={open} onOpenChange={openChange}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{t('Edit project')}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="grid gap-4 sm:grid-cols-[1fr_100px]">
              <div className="space-y-2">
                <Label htmlFor="edit-project-name">{t('Name')}</Label>
                <Input id="edit-project-name" value={name} onChange={(e) => setName(e.target.value)} required />
              </div>
              <div className="space-y-2">
                <Label htmlFor="edit-project-revision">{t('Revision')}</Label>
                <Input id="edit-project-revision" value={revision} maxLength={20} onChange={(e) => setRevision(e.target.value)} placeholder="A" />
              </div>
            </div>
            <div className="space-y-2">
              <Label htmlFor="edit-project-description">{t('Description')}</Label>
              <Textarea
                id="edit-project-description"
                value={description}
                maxLength={255}
                onChange={(e) => setDescription(e.target.value)}
                placeholder={t('What this board or kit is for')}
              />
            </div>
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              {t('Cancel')}
            </Button>
            <Button type="submit" disabled={processing || name.trim().length < 2}>
              {t('Save')}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

function NewRevisionDialog({ project, open, onOpenChange }: DialogProps & { project: Project }) {
  const [revision, setRevision] = useState(project.next_revision)
  const [processing, setProcessing] = useState(false)

  const openChange = (next: boolean) => {
    if (next) setRevision(project.next_revision)
    onOpenChange(next)
  }

  const submit = (e: FormEvent) => {
    e.preventDefault()
    setProcessing(true)
    router.post(
      `/projects/${project.id}/duplicate`,
      { revision: revision.trim() },
      { onSuccess: () => onOpenChange(false), onFinish: () => setProcessing(false) }
    )
  }

  return (
    <Dialog open={open} onOpenChange={openChange}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{t('New revision')}</DialogTitle>
            <DialogDescription>
              {project.revision
                ? tn('Copies revision {revision} and its {count} line into a new draft project, with the same matches. This one stays as it is, with its build history.', 'Copies revision {revision} and its {count} lines into a new draft project, with the same matches. This one stays as it is, with its build history.', project.lines.length, { revision: project.revision })
                : tn('Copies this project and its {count} line into a new draft project, with the same matches. This one stays as it is, with its build history.', 'Copies this project and its {count} lines into a new draft project, with the same matches. This one stays as it is, with its build history.', project.lines.length)}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2 py-4">
            <Label htmlFor="new-revision">{t('Revision')}</Label>
            <Input id="new-revision" value={revision} maxLength={20} onChange={(e) => setRevision(e.target.value)} className="w-32 font-mono" />
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              {t('Cancel')}
            </Button>
            <Button type="submit" disabled={processing}>
              <Copy className="size-4" />
              {t('Create revision')}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

function AddLineDialog({
  projectId,
  partOptions,
  open,
  onOpenChange,
}: DialogProps & { projectId: number; partOptions: ComboboxOption[] }) {
  const [partId, setPartId] = useState(NONE)
  const [designation, setDesignation] = useState('')
  const [reference, setReference] = useState('')
  const [designators, setDesignators] = useState('')
  const [quantity, setQuantity] = useState('1')
  const [processing, setProcessing] = useState(false)

  const reset = () => {
    setPartId(NONE)
    setDesignation('')
    setReference('')
    setDesignators('')
    setQuantity('1')
  }

  const quantityValue = Number(quantity)
  const valid =
    Number.isInteger(quantityValue) && quantityValue >= 1 && (partId !== NONE || designation.trim() !== '' || reference.trim() !== '')

  const submit = (e: FormEvent) => {
    e.preventDefault()
    if (!valid) return
    setProcessing(true)
    router.post(
      `/projects/${projectId}/project_lines`,
      {
        project_line: {
          part_id: partId === NONE ? '' : partId,
          designation: designation.trim(),
          raw_reference: reference.trim(),
          designators: designators.trim(),
          quantity: quantityValue,
        },
      },
      {
        preserveScroll: true,
        onSuccess: () => {
          reset()
          onOpenChange(false)
        },
        onFinish: () => setProcessing(false),
      }
    )
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{t('Add line')}</DialogTitle>
            <DialogDescription>
              {t('Pick a part from the inventory, or describe a component you don\'t stock yet so it shows up as missing.')}
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="line-part">{t('Part')}</Label>
              <Combobox
                id="line-part"
                options={partOptions}
                value={partId}
                onValueChange={(value) => setPartId(value || NONE)}
                placeholder={t('Not in inventory')}
                searchPlaceholder={t('Search parts…')}
                className="w-full"
              />
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="line-designation">{t('Designation')}</Label>
                <Input
                  id="line-designation"
                  value={designation}
                  onChange={(e) => setDesignation(e.target.value)}
                  placeholder={partId === NONE ? t('e.g. ESP32-C3 module') : t('Defaults to the part name')}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="line-reference">{t('Reference (MPN)')}</Label>
                <Input
                  id="line-reference"
                  value={reference}
                  onChange={(e) => setReference(e.target.value)}
                  placeholder={partId === NONE ? t('Optional') : t('Defaults to the part MPN')}
                />
              </div>
            </div>
            <div className="grid gap-4 sm:grid-cols-[1fr_120px]">
              <div className="space-y-2">
                <Label htmlFor="line-designators">{t('Designators')}</Label>
                <Input id="line-designators" value={designators} onChange={(e) => setDesignators(e.target.value)} placeholder={t('e.g. R1, R2')} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="line-quantity">{t('Quantity')}</Label>
                <Input
                  id="line-quantity"
                  type="number"
                  min={1}
                  value={quantity}
                  onChange={(e) => setQuantity(e.target.value)}
                  className="font-mono"
                />
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              {t('Cancel')}
            </Button>
            <Button type="submit" disabled={processing || !valid}>
              <Plus className="size-4" />
              {t('Add line')}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
