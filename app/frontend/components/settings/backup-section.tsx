import { useRef, useState } from 'react'
import { router } from '@inertiajs/react'
import { Download, FileArchive, Upload } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Field, FieldContent, FieldDescription, FieldLabel } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

import type { OrganizationSettings } from './types'

// Download the organization as a backup archive, or restore one into a new
// organization (BackupsController).
export function BackupSection({ organization }: { organization: OrganizationSettings }) {
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [file, setFile] = useState<File | null>(null)
  const [name, setName] = useState('')
  const [processing, setProcessing] = useState(false)

  const restore = () => {
    if (!file) return
    router.post(
      '/backup/import',
      { file, name },
      {
        forceFormData: true,
        onStart: () => setProcessing(true),
        onFinish: () => setProcessing(false),
      },
    )
  }

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">Backup</h2>
        <p className="max-w-xl text-sm text-muted-foreground">
          Export everything to keep a copy, or to move the organization to another MakerStorage install.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Export organization</CardTitle>
          <CardDescription>
            Downloads a ZIP archive of <span className="font-medium text-foreground">{organization.name}</span>: parts,
            categories, footprints, tags, storage zones, stock levels and movements, suppliers, orders, projects, settings
            and attached files, as JSON with a CSV copy of each table. Members and supplier API keys are not included.
          </CardDescription>
        </CardHeader>
        <CardFooter className="justify-end border-t">
          <Button asChild>
            <a href="/backup/export" download>
              <Download className="size-4" /> Download backup
            </a>
          </Button>
        </CardFooter>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Restore a backup</CardTitle>
          <CardDescription>
            Creates a new organization from a backup archive, with you as its owner. Existing organizations are left
            untouched; invite members again once it's restored.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex flex-wrap items-center gap-3">
            <Button type="button" variant="outline" onClick={() => fileInputRef.current?.click()}>
              <Upload className="size-4" /> Choose archive
            </Button>
            {file && (
              <span className="flex min-w-0 items-center gap-1.5 text-sm text-muted-foreground">
                <FileArchive className="size-4 shrink-0" />
                <span className="truncate">{file.name}</span>
              </span>
            )}
            <input
              ref={fileInputRef}
              type="file"
              accept=".zip,application/zip"
              className="hidden"
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            />
          </div>
          <Field>
            <FieldLabel><Label htmlFor="backup-name">Organization name</Label></FieldLabel>
            <FieldContent>
              <Input
                id="backup-name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Keep the name from the backup"
              />
            </FieldContent>
            <FieldDescription>Optional. Useful to tell the copy apart from the original.</FieldDescription>
          </Field>
        </CardContent>
        <CardFooter className="justify-end border-t">
          <Button type="button" disabled={!file || processing} onClick={restore}>
            {processing ? 'Restoring…' : 'Restore into a new organization'}
          </Button>
        </CardFooter>
      </Card>
    </div>
  )
}
