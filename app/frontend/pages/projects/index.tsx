import { Head, Link, router } from '@inertiajs/react'
import { FormEvent, useRef, useState } from 'react'
import { ClipboardList, Plus, Upload, Trash2, CheckCircle2, AlertTriangle, Lock } from 'lucide-react'

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
import { t, intlLocale } from '@/lib/i18n'

interface ProjectSummary {
  id: number
  name: string
  reference: string | null
  status: 'draft' | 'confirmed'
  reserved: boolean
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
  return new Date(iso).toLocaleDateString(intlLocale(), { day: '2-digit', month: '2-digit', year: 'numeric' })
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
        <PageHeader title={t('Projects')} subtitle={t('Import a project BOM and check stock availability')}>
          {canWrite ? (
            <Button size="sm" onClick={() => setOpen(true)}>
              <Plus className="size-4" />
              {t('New project')}
            </Button>
          ) : (
            <ReadOnlyBadge />
          )}
        </PageHeader>
      }
    >
      <Head title={t('Projects')} />

      <div className="space-y-6">
        <FlashMessages />

        {projects.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
              <div className="flex size-11 items-center justify-center rounded-xl bg-muted text-muted-foreground">
                <ClipboardList className="size-[22px]" />
              </div>
              <p className="font-semibold">{t('No projects yet')}</p>
              <p className="max-w-sm text-sm text-muted-foreground">
                {t('Upload a bill of materials (CSV, or a KiCad / EasyEDA export) to match each component against your inventory and see what you can build.')}
              </p>
            </CardContent>
          </Card>
        ) : (
          <Card className="overflow-hidden py-0">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>{t('Project')}</TableHead>
                  <TableHead>{t('Reference')}</TableHead>
                  <TableHead>{t('Status')}</TableHead>
                  <TableHead>{t('Availability')}</TableHead>
                  <TableHead className="text-right">{t('Lines')}</TableHead>
                  <TableHead>{t('Created')}</TableHead>
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
                      <div className="flex items-center gap-1.5">
                        <Badge variant="outline">{project.status === 'draft' ? t('Draft') : t('Confirmed')}</Badge>
                        {project.reserved && (
                          <Badge variant="outline" title={t('Stock reserved for this project')}>
                            <Lock className="size-3.5" /> {t('Reserved')}
                          </Badge>
                        )}
                      </div>
                    </TableCell>
                    <TableCell>
                      {project.buildable ? (
                        <Badge variant="outline" className="bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400">
                          <CheckCircle2 className="size-3.5" /> {t('Buildable')}
                        </Badge>
                      ) : (
                        <Badge variant="outline" className="bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-400">
                          <AlertTriangle className="size-3.5" />
                          {t('{count} to resolve', { count: project.short_count + project.unmatched_count })}
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
                          aria-label={t('Delete project')}
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
              <DialogTitle>{t('New project')}</DialogTitle>
              <DialogDescription>
                {t('Upload a BOM CSV, or a KiCad export (BOM CSV or the netlist XML) or an EasyEDA BOM. Columns are auto-detected (designation, MPN, SKU, value, footprint, quantity); KiCad lines are matched by MPN, supplier part number, then value + footprint. Review the matches before building.')}
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="project-name">{t('Project name')}</Label>
                <Input
                  id="project-name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder={t('e.g. Weather station v2')}
                  autoFocus
                />
                <p className="text-xs text-muted-foreground">{t('Optional — defaults to the file name.')}</p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="project-file">{t('BOM file (CSV or KiCad XML)')}</Label>
                <Input
                  ref={fileInput}
                  id="project-file"
                  type="file"
                  accept=".csv,text/csv,.xml,application/xml,text/xml"
                  onChange={(e) => setFileName(e.target.value.split(/[\\/]/).pop() ?? '')}
                  required
                />
              </div>
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                {t('Cancel')}
              </Button>
              <Button type="submit" disabled={processing || !fileName}>
                <Upload className="size-4" />
                {t('Import & match')}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Delete confirmation */}
      <AlertDialog open={deleteId !== null} onOpenChange={(o) => !o && setDeleteId(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('Delete this project?')}</AlertDialogTitle>
            <AlertDialogDescription>
              {t('This removes the BOM and its matches. Stock and movements are not affected.')}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('Cancel')}</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (deleteId !== null) router.delete(`/projects/${deleteId}`, { preserveScroll: true })
                setDeleteId(null)
              }}
            >
              {t('Delete')}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </AppLayout>
  )
}
