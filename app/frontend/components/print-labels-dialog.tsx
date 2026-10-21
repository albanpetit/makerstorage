import { ReactNode, useState } from 'react'
import { Printer } from 'lucide-react'
import { toast } from 'sonner'

import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  DEFAULT_LABEL_FORMAT,
  LABEL_FORMATS,
  type LabelFormatId,
  type LabelItem,
  isLabelFormatId,
  printLabels,
} from '@/lib/labels'
import { t, tn } from '@/lib/i18n'

const FORMAT_STORAGE_KEY = 'makerstorage.labelFormat'

function storedFormat(): LabelFormatId {
  try {
    const value = window.localStorage.getItem(FORMAT_STORAGE_KEY)
    return isLabelFormatId(value) ? value : DEFAULT_LABEL_FORMAT
  } catch {
    return DEFAULT_LABEL_FORMAT
  }
}

interface PrintLabelsDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  count: number
  // Resolves the labels to print; may fetch (e.g. parts selected beyond the
  // loaded page).
  loadItems: () => Promise<LabelItem[]>
  title: string
  description?: string
  // Extra options shown above the format picker (e.g. "include sub-zones").
  children?: ReactNode
}

// Picks a label format (remembered per browser) and prints QR labels for
// +items+ through the browser's print dialog.
export function PrintLabelsDialog({ open, onOpenChange, count, loadItems, title, description, children }: PrintLabelsDialogProps) {
  const [format, setFormat] = useState<LabelFormatId>(storedFormat)

  const chooseFormat = (value: string) => {
    if (!isLabelFormatId(value)) return
    setFormat(value)
    try {
      window.localStorage.setItem(FORMAT_STORAGE_KEY, value)
    } catch {
      // Storage can be unavailable (private mode); the choice just isn't kept.
    }
  }

  const print = () => {
    // Open the print window while still in the click handler: popup blockers
    // refuse window.open once the labels have been loaded asynchronously.
    const target = window.open('', '_blank')
    loadItems()
      .then((items) => printLabels(items, format, target))
      .catch(() => {
        target?.close()
        toast.error(t('Could not prepare the labels.'))
      })
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>
            {description ?? t('Each label carries a QR code that opens the scanner on this record.')}
          </DialogDescription>
        </DialogHeader>

        {children}

        <div className="min-w-0 space-y-2">
          <Label htmlFor="label-format">{t('Label format')}</Label>
          <Select value={format} onValueChange={chooseFormat}>
            <SelectTrigger id="label-format" className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent position="popper">
              {(Object.keys(LABEL_FORMATS) as LabelFormatId[]).map((id) => (
                <SelectItem key={id} value={id}>{LABEL_FORMATS[id].name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <p className="text-xs text-muted-foreground">
            {t('In the print dialog, keep the scale at 100% and disable headers and footers.')}
          </p>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>{t('Cancel')}</Button>
          <Button disabled={count === 0} onClick={print}>
            <Printer className="size-4" />
            {tn('Print {count} label', 'Print {count} labels', count)}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
