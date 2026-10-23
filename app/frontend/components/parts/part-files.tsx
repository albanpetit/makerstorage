import { router } from '@inertiajs/react'
import { DragEvent, useRef, useState } from 'react'
import { Download, FileText, Paperclip, Trash2, Upload } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
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
import { formatFileSize } from '@/lib/kicad-files'
import { t, intlLocale } from '@/lib/i18n'

export interface PartFile {
  id: number
  filename: string
  content_type: string
  byte_size: number
  created_at: string
  url: string
  datasheet: boolean
}

interface PartFilesProps {
  partId: number
  files: PartFile[]
  canWrite: boolean
  // Called once an upload or removal is done, to refresh the sheet.
  onChange: () => void
}

// The part's datasheet and other files (application notes, 3D models,
// firmware…): open or download them, and, for writers, add (button or drop)
// and remove them. Keep the limits in step with Part::MAX_ATTACHMENTS.
export function PartFiles({ partId, files, canWrite, onChange }: PartFilesProps) {
  const fileInput = useRef<HTMLInputElement>(null)
  const [uploading, setUploading] = useState(false)
  const [dragging, setDragging] = useState(false)
  const [removeFile, setRemoveFile] = useState<PartFile | null>(null)

  const upload = (list: FileList | null) => {
    if (!list || list.length === 0) return
    const formData = new FormData()
    Array.from(list).forEach((file) => formData.append('files[]', file))
    setUploading(true)
    router.post(`/parts/${partId}/attachments`, formData, {
      preserveScroll: true,
      preserveState: true,
      onFinish: () => {
        setUploading(false)
        if (fileInput.current) fileInput.current.value = ''
        onChange()
      },
    })
  }

  const remove = (file: PartFile) => {
    router.delete(`/parts/${partId}/attachments/${file.id}`, {
      preserveScroll: true,
      preserveState: true,
      onFinish: onChange,
    })
  }

  const onDrop = (e: DragEvent) => {
    e.preventDefault()
    setDragging(false)
    if (canWrite) upload(e.dataTransfer.files)
  }

  return (
    <div
      onDragOver={(e) => {
        if (!canWrite) return
        e.preventDefault()
        setDragging(true)
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={onDrop}
    >
      <div className="mb-2 flex items-center justify-between">
        <h3 className="text-sm font-semibold">{t('Files')}</h3>
        {canWrite && (
          <>
            <Button size="sm" variant="ghost" className="h-7" disabled={uploading} onClick={() => fileInput.current?.click()}>
              <Upload className="size-3.5" />
              {t('Add files')}
            </Button>
            <Input
              ref={fileInput}
              type="file"
              multiple
              className="hidden"
              aria-label={t('Files')}
              onChange={(e) => upload(e.target.files)}
            />
          </>
        )}
      </div>
      {files.length === 0 ? (
        <p className={`rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground ${dragging ? 'border-primary bg-accent' : ''}`}>
          {canWrite ? t('No files yet. Drop a datasheet, an application note or a 3D model here.') : t('No files yet.')}
        </p>
      ) : (
        <ul className={`divide-y rounded-lg border ${dragging ? 'border-primary bg-accent' : ''}`}>
          {files.map((file) => (
            <li key={file.id} className="flex items-center gap-2 px-3 py-2 text-sm">
              {file.datasheet ? (
                <FileText className="size-4 shrink-0 text-muted-foreground" />
              ) : (
                <Paperclip className="size-4 shrink-0 text-muted-foreground" />
              )}
              <a
                href={file.url}
                target="_blank"
                rel="noopener noreferrer"
                className="min-w-0 truncate hover:underline"
                title={file.filename}
              >
                {file.filename}
              </a>
              {file.datasheet && <Badge variant="outline" className="shrink-0">{t('Datasheet')}</Badge>}
              <span className="ml-auto shrink-0 text-xs text-muted-foreground">
                {formatFileSize(file.byte_size)} · {new Date(file.created_at).toLocaleDateString(intlLocale())}
              </span>
              <Button variant="ghost" size="icon-sm" asChild>
                <a href={`${file.url}?disposition=attachment`} download aria-label={t('Download {name}', { name: file.filename })}>
                  <Download className="size-4 text-muted-foreground" />
                </a>
              </Button>
              {canWrite && (
                <Button variant="ghost" size="icon-sm" aria-label={t('Remove {name}', { name: file.filename })} onClick={() => setRemoveFile(file)}>
                  <Trash2 className="size-4 text-muted-foreground" />
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}

      <AlertDialog open={removeFile !== null} onOpenChange={(o) => !o && setRemoveFile(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('Remove {name}?', { name: removeFile?.filename ?? '' })}</AlertDialogTitle>
            <AlertDialogDescription>{t('The file is deleted from this part.')}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('Cancel')}</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (removeFile) remove(removeFile)
                setRemoveFile(null)
              }}
            >
              {t('Remove')}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}
