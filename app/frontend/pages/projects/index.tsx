import { Head, Link, router } from '@inertiajs/react'
import { FormEvent, useRef, useState } from 'react'
import { ClipboardList, Plus, Upload, Trash2, CheckCircle2, AlertTriangle, Lock, Paperclip, GitBranch } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { KICAD_ACCEPT, KICAD_FILE } from '@/lib/kicad-files'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { ReadOnlyBadge } from '@/components/read-only-badge'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { GithubFields, type GithubLinkData } from '@/components/projects/github-fields'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
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

interface ProjectSummary {
  id: number
  name: string
  reference: string | null
  revision: string | null
  status: 'draft' | 'confirmed'
  reserved: boolean
  line_count: number
  buildable: boolean
  short_count: number
  unmatched_count: number
  checked_at: string | null
  created_at: string
  file_count: number
  github_repository: string | null
}

interface ProjectsPageProps {
  projects: ProjectSummary[]
  github_token_configured: boolean
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, { day: '2-digit', month: '2-digit', year: 'numeric' })
}

export default function ProjectsIndex({ projects, github_token_configured }: ProjectsPageProps) {
  const { canWrite } = usePermissions()
  const [open, setOpen] = useState(false)
  const [name, setName] = useState('')
  const [fileName, setFileName] = useState('')
  const [processing, setProcessing] = useState(false)
  const [deleteId, setDeleteId] = useState<number | null>(null)
  const fileInput = useRef<HTMLInputElement>(null)
  const [source, setSource] = useState<'files' | 'github'>('files')
  const [github, setGithub] = useState<GithubLinkData>({ repository: '', ref: '', path: '' })

  const reset = () => {
    setOpen(false)
    setName('')
    setFileName('')
    setGithub({ repository: '', ref: '', path: '' })
  }

  const submit = (e: FormEvent) => {
    e.preventDefault()
    if (source === 'github') {
      setProcessing(true)
      router.post('/projects', { ...github, name: name.trim() }, { onSuccess: reset, onFinish: () => setProcessing(false) })
      return
    }

    const files = Array.from(fileInput.current?.files ?? [])
    if (files.length === 0 && !name.trim()) return

    const formData = new FormData()
    if (files.length === 1 && !KICAD_FILE.test(files[0].name)) {
      formData.append('file', files[0])
    } else {
      files.forEach((file) => formData.append('files[]', file))
    }
    if (name.trim()) formData.append('name', name.trim())

    setProcessing(true)
    router.post('/projects', formData, {
      onSuccess: reset,
      onFinish: () => setProcessing(false),
    })
  }

  return (
    <AppLayout
      header={
        <PageHeader title="Projects" subtitle="Build a project BOM by hand or import its KiCad files or BOM, and check stock availability">
          {canWrite ? (
            <Button size="sm" onClick={() => setOpen(true)}>
              <Plus className="size-4" />
              New project
            </Button>
          ) : (
            <ReadOnlyBadge />
          )}
        </PageHeader>
      }
    >
      <Head title="Projects" />

      <div className="space-y-6">
        <FlashMessages />

        {projects.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
              <div className="flex size-11 items-center justify-center rounded-xl bg-muted text-muted-foreground">
                <ClipboardList className="size-[22px]" />
              </div>
              <p className="font-semibold">No projects yet</p>
              <p className="max-w-sm text-sm text-muted-foreground">
                Start a project and add its parts by hand, or upload a KiCad project (its files or a ZIP of the folder) or a bill of materials (CSV, or a KiCad / EasyEDA export) to match each component against your inventory and see what you can build.
              </p>
            </CardContent>
          </Card>
        ) : (
          <Card className="overflow-hidden py-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Project</TableHead>
                  <TableHead>Reference</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Availability</TableHead>
                  <TableHead className="text-right">Lines</TableHead>
                  <TableHead>Created</TableHead>
                  <TableHead className="w-10" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {projects.map((project) => (
                  <TableRow key={project.id} className="cursor-pointer" onClick={() => router.visit(`/projects/${project.id}`)}>
                    <TableCell className="font-medium">
                      <div className="flex items-center gap-2">
                        <Link href={`/projects/${project.id}`} className="hover:underline" onClick={(e) => e.stopPropagation()}>
                          {project.name}
                        </Link>
                        {project.revision && (
                          <Badge variant="outline" className="font-mono text-xs">rev {project.revision}</Badge>
                        )}
                        {project.github_repository && (
                          <span
                            className="inline-flex items-center gap-0.5 text-xs font-normal text-muted-foreground"
                            title={`Linked to ${project.github_repository} on GitHub`}
                          >
                            <GitBranch className="size-3.5" />
                          </span>
                        )}
                        {project.file_count > 0 && (
                          <span
                            className="inline-flex items-center gap-0.5 text-xs font-normal text-muted-foreground"
                            title={`${project.file_count} KiCad file${project.file_count !== 1 ? 's' : ''}`}
                          >
                            <Paperclip className="size-3.5" />
                            {project.file_count}
                          </span>
                        )}
                      </div>
                    </TableCell>
                    <TableCell className="font-mono text-xs text-muted-foreground">{project.reference}</TableCell>
                    <TableCell>
                      <div className="flex items-center gap-1.5">
                        <Badge variant="outline" className="capitalize">{project.status}</Badge>
                        {project.reserved && (
                          <Badge variant="outline" title="Stock reserved for this project">
                            <Lock className="size-3.5" /> Reserved
                          </Badge>
                        )}
                      </div>
                    </TableCell>
                    <TableCell>
                      {project.line_count === 0 ? (
                        <span className="text-xs text-muted-foreground">No lines yet</span>
                      ) : project.buildable ? (
                        <Badge variant="outline" className="bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400">
                          <CheckCircle2 className="size-3.5" /> Buildable
                        </Badge>
                      ) : (
                        <Badge variant="outline" className="bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400">
                          <AlertTriangle className="size-3.5" />
                          {project.short_count + project.unmatched_count} to resolve
                        </Badge>
                      )}
                    </TableCell>
                    <TableCell className="text-right font-mono">{project.line_count}</TableCell>
                    <TableCell className="text-xs text-muted-foreground">{formatDate(project.created_at)}</TableCell>
                    <TableCell>
                      {canWrite && (
                        <Button
                          variant="ghost"
                          size="icon-sm"
                          aria-label="Delete project"
                          onClick={(e) => {
                            e.stopPropagation()
                            setDeleteId(project.id)
                          }}
                        >
                          <Trash2 className="size-4 text-muted-foreground" />
                        </Button>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </Card>
        )}
      </div>

      {/* Upload dialog */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-md">
          <form onSubmit={submit}>
            <DialogHeader>
              <DialogTitle>New project</DialogTitle>
              <DialogDescription>
                Give it a name to start empty and add parts by hand, or upload the KiCad project files (.kicad_pro, .kicad_sch, .kicad_pcb…) or a ZIP of the project folder, or fetch them from a GitHub repository: they're kept with the project and the BOM is read from the schematics. A BOM export also works: a CSV, a KiCad BOM CSV or netlist XML, or an EasyEDA BOM. Lines are matched by MPN, supplier part number, then value + footprint. Review the matches before building.
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="project-name">Project name</Label>
                <Input
                  id="project-name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="e.g. Weather station v2"
                  autoFocus
                />
                <p className="text-xs text-muted-foreground">
                  {source === 'github'
                    ? 'Optional — defaults to the folder or repository name.'
                    : 'Required without a file; defaults to the file name otherwise.'}
                </p>
              </div>

              <div className="grid grid-cols-2 gap-1 rounded-lg bg-muted p-1" role="group" aria-label="Source">
                <Button
                  type="button"
                  size="sm"
                  variant={source === 'files' ? 'outline' : 'ghost'}
                  aria-pressed={source === 'files'}
                  onClick={() => setSource('files')}
                >
                  <Upload className="size-4" />
                  Upload files
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant={source === 'github' ? 'outline' : 'ghost'}
                  aria-pressed={source === 'github'}
                  onClick={() => setSource('github')}
                >
                  <GitBranch className="size-4" />
                  From GitHub
                </Button>
              </div>

              {source === 'files' ? (
                <div className="space-y-2">
                  <Label htmlFor="project-file">KiCad files or BOM, optional</Label>
                  <Input
                    ref={fileInput}
                    id="project-file"
                    type="file"
                    multiple
                    accept={`${KICAD_ACCEPT},.csv,text/csv,.xml,application/xml,text/xml`}
                    onChange={(e) => setFileName(e.target.value.split(/[\\/]/).pop() ?? '')}
                  />
                  <p className="text-xs text-muted-foreground">Select several KiCad files at once, or a single ZIP or BOM file.</p>
                </div>
              ) : (
                <GithubFields data={github} onChange={setGithub} tokenConfigured={github_token_configured} />
              )}
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button
                type="submit"
                disabled={processing || (source === 'files' ? !fileName && !name.trim() : !github.repository.trim())}
              >
                {source === 'github' ? <GitBranch className="size-4" /> : fileName ? <Upload className="size-4" /> : <Plus className="size-4" />}
                {source === 'github' ? 'Fetch & match' : fileName ? 'Import & match' : 'Create empty project'}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation */}
      <AlertDialog open={deleteId !== null} onOpenChange={(o) => !o && setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete this project?</AlertDialogTitle>
            <AlertDialogDescription>
              This removes the BOM, its matches and its build history. Stock and movements are not affected.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (deleteId !== null) router.delete(`/projects/${deleteId}`, { preserveScroll: true })
                setDeleteId(null)
              }}
            >
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </AppLayout>
  )
}
