import { ReactNode, useEffect, useState } from 'react'
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
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { usePermissions } from '@/hooks/use-permissions'
import {
  DEFAULT_LABEL_FORMAT,
  LABEL_FORMATS,
  type LabelFormatId,
  type LabelItem,
  isLabelFormatId,
  printLabels,
} from '@/lib/labels'
import { type LabelPrinter, fetchLabelPrinters, printOnLabelPrinter } from '@/lib/label-printers'
import { t, tn } from '@/lib/i18n'

const TARGET_STORAGE_KEY = 'makerstorage.labelFormat'

// Where labels go: a browser format (print dialog) or a network printer
// ("printer:<id>").
export type LabelTarget = LabelFormatId | `printer:${number}`

function printerTarget(printer: LabelPrinter): LabelTarget {
  return `printer:${printer.id}`
}

function storedTarget(): LabelTarget {
  try {
    const value = window.localStorage.getItem(TARGET_STORAGE_KEY)
    if (isLabelFormatId(value) || /^printer:\d+$/.test(value ?? '')) return value as LabelTarget
  } catch {
    // Storage can be unavailable (private mode).
  }
  return DEFAULT_LABEL_FORMAT
}

// The label target remembered in this browser, and the organization's network
// printers (fetched once +active+).
export function useLabelTarget(active: boolean) {
  const [target, setTarget] = useState<LabelTarget>(storedTarget)
  const [printers, setPrinters] = useState<LabelPrinter[] | null>(null)

  useEffect(() => {
    if (!active || printers) return
    fetchLabelPrinters()
      .then((payload) => setPrinters(payload.enabled ? payload.printers : []))
      .catch(() => setPrinters([]))
  }, [active, printers])

  const choose = (value: string) => {
    if (!isLabelFormatId(value) && !/^printer:\d+$/.test(value)) return
    setTarget(value as LabelTarget)
    try {
      window.localStorage.setItem(TARGET_STORAGE_KEY, value)
    } catch {
      // The choice just isn't kept.
    }
  }

  const printer = printers?.find((p) => printerTarget(p) === target) ?? null
  // A remembered printer that was removed (or isn't loaded yet) falls back to
  // the default browser format.
  const effective: LabelTarget = isLabelFormatId(target) ? target : printer ? target : DEFAULT_LABEL_FORMAT

  return { target: effective, printer, printers, choose, loaded: printers !== null }
}

// Sends +items+ to a network printer with a toast for the outcome.
export function printOnPrinterWithToast(printer: LabelPrinter, items: Promise<LabelItem[]>) {
  const job = items.then(async (list) => {
    if (list.length > 0) await printOnLabelPrinter(printer, list)
    return list.length
  })
  toast.promise(job, {
    loading: t('Printing on {name}…', { name: printer.name }),
    success: (n: number) => tn('Sent {count} label to {name}.', 'Sent {count} labels to {name}.', n, { name: printer.name }),
    error: (error: Error) => error.message || t('Could not prepare the labels.'),
  })
}

export function LabelTargetSelect({ id, value, onChange, printers }: {
  id?: string
  value: LabelTarget
  onChange: (value: string) => void
  printers: LabelPrinter[] | null
}) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger id={id} className="w-full">
        <SelectValue />
      </SelectTrigger>
      <SelectContent position="popper">
        {printers && printers.length > 0 && (
          <SelectGroup>
            <SelectLabel>{t('Network printers')}</SelectLabel>
            {printers.map((printer) => (
              <SelectItem key={printer.id} value={printerTarget(printer)}>
                {printer.name} · {printer.size}
              </SelectItem>
            ))}
          </SelectGroup>
        )}
        <SelectGroup>
          <SelectLabel>{t('Browser print dialog')}</SelectLabel>
          {(Object.keys(LABEL_FORMATS) as LabelFormatId[]).map((formatId) => (
            <SelectItem key={formatId} value={formatId}>{LABEL_FORMATS[formatId].name}</SelectItem>
          ))}
        </SelectGroup>
      </SelectContent>
    </Select>
  )
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

// Picks where to print (remembered per browser): a network label printer, or
// a label format for the browser's print dialog.
export function PrintLabelsDialog({ open, onOpenChange, count, loadItems, title, description, children }: PrintLabelsDialogProps) {
  const { canAdminister } = usePermissions()
  const { target, printer, printers, choose } = useLabelTarget(open)

  const print = () => {
    if (printer) {
      printOnPrinterWithToast(printer, loadItems())
      onOpenChange(false)
      return
    }

    // Open the print window while still in the click handler: popup blockers
    // refuse window.open once the labels have been loaded asynchronously.
    const format = target as LabelFormatId
    const printWindow = window.open('', '_blank')
    loadItems()
      .then((items) => printLabels(items, format, printWindow))
      .catch(() => {
        printWindow?.close()
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
          <Label htmlFor="label-format">{t('Print on')}</Label>
          <LabelTargetSelect id="label-format" value={target} onChange={choose} printers={printers} />
          <p className="text-xs text-muted-foreground">
            {printer
              ? t('Sent straight to the printer: load {size} labels.', { size: printer.size })
              : t('In the print dialog, keep the scale at 100% and disable headers and footers.')}
            {!printer && printers?.length === 0 && canAdminister && ` ${t('Brother QL and Zebra printers on your network can print directly: add them in Settings → Label printers.')}`}
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
