import { ReactNode, useState } from 'react'
import { Printer } from 'lucide-react'

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
  items: LabelItem[]
  title: string
  description?: string
  // Extra options shown above the format picker (e.g. "include sub-zones").
  children?: ReactNode
}

// Picks a label format (remembered per browser) and prints QR labels for
// +items+ through the browser's print dialog.
export function PrintLabelsDialog({ open, onOpenChange, items, title, description, children }: PrintLabelsDialogProps) {
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
    void printLabels(items, format)
    onOpenChange(false)
  }

  const count = items.length

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>
            {description ?? 'Each label carries a QR code that opens the scanner on this record.'}
          </DialogDescription>
        </DialogHeader>

        {children}

        <div className="min-w-0 space-y-2">
          <Label htmlFor="label-format">Label format</Label>
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
            In the print dialog, keep the scale at 100% and disable headers and footers.
          </p>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button disabled={count === 0} onClick={print}>
            <Printer className="size-4" />
            Print {count} label{count !== 1 ? 's' : ''}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
