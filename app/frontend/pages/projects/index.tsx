import { Head, Link, router } from '@inertiajs/react'
import { FormEvent, useRef, useState } from 'react'
import { ClipboardList, Plus, Upload, Trash2, CheckCircle2, AlertTriangle } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { usePermissions } from '@/hooks/use-permissions'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { ReadOnlyBadge } from '@/components/read-only-badge'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
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
  status: 'draft' | 'confirmed'
  line_count: number
  buildable: boolean
  short_count: number
  unmatched_count: number
  checked_at: string | null
  created_at: string
}

interface ProjectsPageProps {
  projects: ProjectSummary[]
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, { day: '2-digit', month: '2-digit', year: 'numeric' })
}

export default function ProjectsIndex({ projects }: ProjectsPageProps) {
  const { canWrite } = usePermissions()
  const [open, setOpen] = useState(false)
  const [name, setName] = useState('')
  const [fileName, setFileName] = useState('')
  const [processing, setProcessing] = useState(false)
  const [deleteId, setDeleteId] = useState<number | null>(null)
  const fileInput = useRef<HTMLInputElement>(null)

  const submit = (e: FormEvent) => {
    e.preventDefault()
    const file = fileInput.current?.files?.[0]
    if (!file) return

    const formData = new FormData()
    formData.append('file', file)
    if (name.trim()) formData.append('name', name.trim())

    setProcessing(true)
    router.post('/projects', formData, {
      onSuccess: () => {
        setOpen(false)
        setName('')
        setFileName('')
      },
      onFinish: () => setProcessing(false),
    })
  }

  return (
    <AppLayout
      header={
        <PageHeader title="Projects" subtitle="Import a project BOM and check stock availability">
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
                Upload a bill of materials (CSV) to match each component against your inventory and see what you can build.
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
                      <Link href={`/projects/${project.id}`} className="hover:underline" onClick={(e) => e.stopPropagation()}>
                        {project.name}
                      </Link>
                    </TableCell>
                    <TableCell className="font-mono text-xs text-muted-foreground">{project.reference}</TableCell>
                    <TableCell>
                      <Badge variant="outline" className="capitalize">{project.status}</Badge>
                    </TableCell>
                    <TableCell>
                      {project.buildable ? (
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
                Upload a BOM CSV. Columns are auto-detected (designation, MPN, SKU/reference, quantity). We'll match each row against your inventory for you to review.
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
                <p className="text-xs text-muted-foreground">Optional — defaults to the file name.</p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="project-file">BOM file (CSV)</Label>
                <Input
                  ref={fileInput}
                  id="project-file"
                  type="file"
                  accept=".csv,text/csv"
                  onChange={(e) => setFileName(e.target.value.split(/[\\/]/).pop() ?? '')}
                  required
                />
              </div>
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={processing || !fileName}>
                <Upload className="size-4" />
                Import & match
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
              This removes the BOM and its matches. Stock and movements are not affected.
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
