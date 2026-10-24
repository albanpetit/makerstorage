import { useRef, useState } from 'react'
import { CircleAlert, FileText, Image as ImageIcon, Loader2, Sparkles, X } from 'lucide-react'

import { Alert, AlertDescription } from '@/components/ui/alert'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { t } from '@/lib/i18n'

// What POST /parts/extract (PartExtraction) read from the files. Ids are the
// organization's own; parameters are keyed by definition id like the form.
export interface AiEntryResult {
  name: string | null
  mpn: string | null
  manufacturer: string | null
  description: string | null
  value: string | null
  package_type: string | null
  tolerance: string | null
  voltage_rating: string | null
  power_rating: string | null
  category_id: number | null
  footprint_id: number | null
  parameters: Record<string, string>
  quantity: number | null
  rohs_compliant: boolean
  notes: string | null
  existing_part: { id: number; name: string } | null
}

// Server limits (PartExtraction): 4 files, photos up to 5 MB, PDFs up to
// 20 MB, and 20 MB for all the files together.
const MAX_FILES = 4
const MAX_TOTAL_SIZE = 20 * 1024 * 1024
// Phone photos are shrunk before upload: plenty for reading a label, and
// well under the API's 5 MB per image.
const MAX_IMAGE_EDGE = 2000
const SHRINK_ABOVE = 1.5 * 1024 * 1024

function csrfToken(): string {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ?? ''
}

function isPdf(file: File) {
  return file.type === 'application/pdf' || file.name.toLowerCase().endsWith('.pdf')
}

// Re-encodes a large or unusual photo (HEIC on Safari, huge JPEGs) as a JPEG
// of at most MAX_IMAGE_EDGE pixels. Keeps the original when it's already
// small enough or the browser can't decode it.
async function shrinkImage(file: File): Promise<File> {
  const supported = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'].includes(file.type)
  if (supported && file.size <= SHRINK_ABOVE) return file
  try {
    const bitmap = await createImageBitmap(file)
    const scale = Math.min(1, MAX_IMAGE_EDGE / Math.max(bitmap.width, bitmap.height))
    const canvas = document.createElement('canvas')
    canvas.width = Math.round(bitmap.width * scale)
    canvas.height = Math.round(bitmap.height * scale)
    canvas.getContext('2d')?.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    bitmap.close()
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.85))
    if (!blob) return file
    return new File([blob], file.name.replace(/\.[^.]+$/, '') + '.jpg', { type: 'image/jpeg' })
  } catch {
    return file
  }
}

interface AiEntryProps {
  // Called with what Claude read and the files it read it from (the dialog
  // keeps a photo as the part image and a PDF as its datasheet).
  onApply: (result: AiEntryResult, files: File[]) => void
  // Whether a photo / datasheet from these files will be saved with the part.
  attached?: { datasheet: boolean; image: boolean }
}

// AI-assisted entry in the add-part dialog: photos of the part or its label
// and/or its datasheet go to Claude (with the organization's own key), and
// the answer prefills the form for the user to check.
export function AiEntry({ onApply, attached }: AiEntryProps) {
  const [files, setFiles] = useState<File[]>([])
  const [hint, setHint] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<AiEntryResult | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  const addFiles = (list: FileList | null) => {
    if (!list) return
    setError(null)
    const next = [...files, ...Array.from(list)]
    if (next.length > MAX_FILES) setError(t('Add at most {count} files at once.', { count: MAX_FILES }))
    setFiles(next.slice(0, MAX_FILES))
    if (inputRef.current) inputRef.current.value = ''
  }

  const removeFile = (index: number) => setFiles(files.filter((_, i) => i !== index))

  const read = async () => {
    if (files.length === 0) return
    setLoading(true)
    setError(null)
    setResult(null)
    try {
      const prepared = await Promise.all(files.map((file) => (isPdf(file) ? file : shrinkImage(file))))
      // Checked after shrinking: phone photos only count for what is sent.
      if (prepared.reduce((sum, file) => sum + file.size, 0) > MAX_TOTAL_SIZE) {
        setError(t('Together, the files are larger than {size}: send fewer or smaller ones.', { size: '20 MB' }))
        return
      }
      const body = new FormData()
      prepared.forEach((file) => body.append('files[]', file))
      if (hint.trim()) body.append('hint', hint.trim())
      const res = await fetch('/parts/extract', {
        method: 'POST',
        headers: { Accept: 'application/json', 'X-CSRF-Token': csrfToken() },
        credentials: 'same-origin',
        body,
      })
      const json = await res.json().catch(() => ({}))
      if (!res.ok) {
        setError(json.error ?? t('Could not read the files. Please try again.'))
        return
      }
      setResult(json.result)
      onApply(json.result, prepared)
    } catch {
      setError(t('Could not reach the server. Please try again.'))
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="rounded-lg border border-dashed bg-muted/40 p-4">
      <Label className="text-sm font-medium">{t('Fill in with AI')}</Label>
      <p className="mb-2.5 text-xs text-muted-foreground">
        {t('Add a photo of the part or its bag label, or its datasheet: Claude reads it and fills in the form for you to check.')}
      </p>

      <div className="flex flex-col gap-2 sm:flex-row">
        <Input
          ref={inputRef}
          type="file"
          accept="image/*,application/pdf"
          multiple
          className="cursor-pointer sm:max-w-64"
          aria-label={t('Photos or datasheet')}
          onChange={(e) => addFiles(e.target.files)}
          disabled={loading || files.length >= MAX_FILES}
        />
        <Input
          placeholder={t('Optional note, e.g. 10k pull-ups from the red drawer')}
          value={hint}
          maxLength={500}
          onChange={(e) => setHint(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault()
              read()
            }
          }}
        />
        <Button type="button" variant="secondary" onClick={read} disabled={loading || files.length === 0}>
          {loading ? <Loader2 className="size-4 animate-spin" /> : <Sparkles className="size-4" />}
          {loading ? t('Reading…') : t('Read')}
        </Button>
      </div>

      {files.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {files.map((file, index) => (
            <Badge key={`${file.name}-${index}`} variant="outline" className="gap-1 pr-0.5">
              {isPdf(file) ? <FileText className="size-3" /> : <ImageIcon className="size-3" />}
              <span className="max-w-40 truncate">{file.name}</span>
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="size-4 rounded-sm"
                aria-label={t('Remove {name}', { name: file.name })}
                onClick={() => removeFile(index)}
                disabled={loading}
              >
                <X className="size-3" />
              </Button>
            </Badge>
          ))}
        </div>
      )}

      {loading && (
        <p className="mt-2 text-xs text-muted-foreground">{t('A datasheet can take up to a minute to read.')}</p>
      )}
      {error && <p className="mt-2 text-sm text-destructive">{error}</p>}

      {result && (
        <div className="mt-3 space-y-2">
          <p className="text-xs text-muted-foreground">
            {t('The form was filled in from your files. Check each field before saving: AI can misread.')}
          </p>
          {result.existing_part && (
            <Alert>
              <CircleAlert />
              <AlertDescription>
                {t('{mpn} is already in the inventory as {name}.', { mpn: result.mpn ?? '', name: result.existing_part.name })}
              </AlertDescription>
            </Alert>
          )}
          {result.notes && <p className="text-xs italic text-muted-foreground">{result.notes}</p>}
          {attached && (attached.datasheet || attached.image) && (
            <div className="flex flex-wrap gap-2">
              {attached.datasheet && (
                <Badge variant="secondary" className="gap-1">
                  <FileText className="size-3" /> {t('Datasheet will be attached')}
                </Badge>
              )}
              {attached.image && (
                <Badge variant="secondary" className="gap-1">
                  <ImageIcon className="size-3" /> {t('Photo will be the part image')}
                </Badge>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
