import { FormEvent, useState } from 'react'
import { router, useForm } from '@inertiajs/react'
import { Pencil, Plus, Printer, Trash2, TriangleAlert } from 'lucide-react'

import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
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
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Field, FieldContent, FieldDescription, FieldError, FieldLabel } from '@/components/ui/field'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { printOnPrinterWithToast } from '@/components/print-labels-dialog'

import type { LabelPrinterMedia, LabelPrinterProtocol, LabelPrinterSettings } from './types'
import { t } from '@/lib/i18n'

const PROTOCOLS: Record<LabelPrinterProtocol, { name: string; hint: string }> = {
  brother_ql: { name: 'Brother QL', get hint() { return t('QL-710W, QL-720NW, QL-810W, QL-820NWB… (Wi-Fi or Ethernet models)') } },
  zpl: { name: 'Zebra (ZPL)', get hint() { return t('Zebra and ZPL-compatible thermal printers with a network port') } },
}

interface PrinterFormData {
  label_printer: {
    name: string
    protocol: LabelPrinterProtocol
    host: string
    port: string
    media: string
    width_mm: string
    length_mm: string
    dpi: string
  }
}

function formData(printer: LabelPrinterSettings | null): PrinterFormData {
  return {
    label_printer: {
      name: printer?.name ?? '',
      protocol: printer?.protocol ?? 'brother_ql',
      host: printer?.host ?? '',
      port: String(printer?.port ?? 9100),
      media: printer?.media ?? '62x29',
      width_mm: printer?.width_mm?.toString() ?? '50.8',
      length_mm: printer?.length_mm?.toString() ?? (printer?.protocol === 'zpl' ? '25.4' : '29'),
      dpi: String(printer?.dpi ?? 203),
    },
  }
}

function PrinterFormDialog({ printer, media, open, onOpenChange }: {
  printer: LabelPrinterSettings | null
  media: LabelPrinterMedia[]
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const form = useForm<PrinterFormData>(formData(printer))
  const data = form.data.label_printer
  const set = (patch: Partial<PrinterFormData['label_printer']>) => form.setData('label_printer', { ...data, ...patch })
  const error = (field: string) => form.errors[`label_printer.${field}` as keyof typeof form.errors]
  const continuous = media.find((m) => m.id === data.media)?.continuous ?? false

  const submit = (e: FormEvent) => {
    e.preventDefault()
    const options = { preserveScroll: true, onSuccess: () => onOpenChange(false) }
    if (printer) form.patch(`/label_printers/${printer.id}`, options)
    else form.post('/label_printers', options)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{printer ? t('Edit printer') : t('Add a label printer')}</DialogTitle>
          <DialogDescription>{t('The server sends labels to the printer\'s network port, so it must be reachable from the server.')}</DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="flex min-w-0 flex-col gap-4">
          <Field>
            <FieldLabel><Label htmlFor="printer-name">{t('Name')}</Label></FieldLabel>
            <FieldContent>
              <Input id="printer-name" placeholder={t('e.g. Workshop QL-820')} value={data.name} onChange={(e) => set({ name: e.target.value })} />
            </FieldContent>
            {error('name') && <FieldError>{error('name')}</FieldError>}
          </Field>

          <Field>
            <FieldLabel><Label htmlFor="printer-protocol">{t('Printer')}</Label></FieldLabel>
            <FieldContent>
              <Select value={data.protocol} onValueChange={(value) => set({ protocol: value as LabelPrinterProtocol, length_mm: value === 'zpl' ? '25.4' : '29' })}>
                <SelectTrigger id="printer-protocol" className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {(Object.keys(PROTOCOLS) as LabelPrinterProtocol[]).map((key) => (
                    <SelectItem key={key} value={key}>{PROTOCOLS[key].name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <FieldDescription>{PROTOCOLS[data.protocol].hint}</FieldDescription>
            </FieldContent>
          </Field>

          <div className="grid grid-cols-[1fr_7rem] gap-3">
            <Field>
              <FieldLabel><Label htmlFor="printer-host">{t('IP address or host name')}</Label></FieldLabel>
              <FieldContent>
                <Input id="printer-host" placeholder="192.168.1.50" value={data.host} onChange={(e) => set({ host: e.target.value })} />
              </FieldContent>
              {error('host') && <FieldError>{error('host')}</FieldError>}
            </Field>
            <Field>
              <FieldLabel><Label htmlFor="printer-port">{t('Port')}</Label></FieldLabel>
              <FieldContent>
                <Input id="printer-port" inputMode="numeric" value={data.port} onChange={(e) => set({ port: e.target.value })} />
              </FieldContent>
              {error('port') && <FieldError>{error('port')}</FieldError>}
            </Field>
          </div>

          {data.protocol === 'brother_ql' ? (
            <div className="grid grid-cols-[1fr_7rem] gap-3">
              <Field>
                <FieldLabel><Label htmlFor="printer-media">{t('Label roll')}</Label></FieldLabel>
                <FieldContent>
                  <Select value={data.media} onValueChange={(value) => set({ media: value })}>
                    <SelectTrigger id="printer-media" className="w-full"><SelectValue /></SelectTrigger>
                    <SelectContent position="popper">
                      {media.map((m) => <SelectItem key={m.id} value={m.id}>{m.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </FieldContent>
                {error('media') && <FieldError>{error('media')}</FieldError>}
              </Field>
              {continuous && (
                <Field>
                  <FieldLabel><Label htmlFor="printer-length">{t('Length (mm)')}</Label></FieldLabel>
                  <FieldContent>
                    <Input id="printer-length" inputMode="decimal" value={data.length_mm} onChange={(e) => set({ length_mm: e.target.value })} />
                  </FieldContent>
                  {error('length_mm') && <FieldError>{error('length_mm')}</FieldError>}
                </Field>
              )}
            </div>
          ) : (
            <div className="grid grid-cols-3 gap-3">
              <Field>
                <FieldLabel><Label htmlFor="printer-width">{t('Width (mm)')}</Label></FieldLabel>
                <FieldContent>
                  <Input id="printer-width" inputMode="decimal" value={data.width_mm} onChange={(e) => set({ width_mm: e.target.value })} />
                </FieldContent>
                {error('width_mm') && <FieldError>{error('width_mm')}</FieldError>}
              </Field>
              <Field>
                <FieldLabel><Label htmlFor="printer-length">{t('Height (mm)')}</Label></FieldLabel>
                <FieldContent>
                  <Input id="printer-length" inputMode="decimal" value={data.length_mm} onChange={(e) => set({ length_mm: e.target.value })} />
                </FieldContent>
                {error('length_mm') && <FieldError>{error('length_mm')}</FieldError>}
              </Field>
              <Field>
                <FieldLabel><Label htmlFor="printer-dpi">{t('Resolution')}</Label></FieldLabel>
                <FieldContent>
                  <Select value={data.dpi} onValueChange={(value) => set({ dpi: value })}>
                    <SelectTrigger id="printer-dpi" className="w-full"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {['203', '300', '600'].map((dpi) => <SelectItem key={dpi} value={dpi}>{dpi} dpi</SelectItem>)}
                    </SelectContent>
                  </Select>
                </FieldContent>
              </Field>
            </div>
          )}

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>{t('Cancel')}</Button>
            <Button type="submit" disabled={form.processing}>{printer ? t('Save') : t('Add printer')}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

// Network label printers the server prints to directly (LabelPrintersController).
export function PrintersSection({ printers, media, enabled }: {
  printers: LabelPrinterSettings[]
  media: LabelPrinterMedia[]
  enabled: boolean
}) {
  // The printer being edited; null while adding one. The key remounts the form
  // with that printer's values.
  const [editing, setEditing] = useState<{ printer: LabelPrinterSettings | null; key: number } | null>(null)
  const [removing, setRemoving] = useState<LabelPrinterSettings | null>(null)

  const testPrint = (printer: LabelPrinterSettings) =>
    printOnPrinterWithToast(printer, Promise.resolve([{ code: 'TEST', title: 'MakerStorage', lines: [printer.name, printer.size] }]))

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">{t('Label printers')}</h2>
        <p className="max-w-xl text-sm text-muted-foreground">
          {t('Print QR labels straight to a Brother QL or Zebra printer on your network, without the browser\'s print dialog. Other printers (DYMO, USB-only models) keep printing through the browser.')}
        </p>
      </div>

      {!enabled && (
        <Alert>
          <TriangleAlert />
          <AlertTitle>{t('Network printing is turned off on this server')}</AlertTitle>
          <AlertDescription>{t('The server\'s administrator set NETWORK_PRINTING=false. Labels print through the browser.')}</AlertDescription>
        </Alert>
      )}

      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-4">
          <div className="space-y-1.5">
            <CardTitle>{t('Printers')}</CardTitle>
            <CardDescription>{t('Members pick one in the print dialog. Only addresses on a local network (10.x, 172.16–31.x, 192.168.x) and printer ports (9100–9109, 6101) are accepted.')}</CardDescription>
          </div>
          <Button type="button" size="sm" onClick={() => setEditing({ printer: null, key: Date.now() })}>
            <Plus className="size-4" />
            {t('Add printer')}
          </Button>
        </CardHeader>
        <CardContent>
          {printers.length === 0 ? (
            <p className="rounded-lg border border-dashed p-4 text-center text-sm text-muted-foreground">{t('No printer yet.')}</p>
          ) : (
            <div className="divide-y">
              {printers.map((printer) => (
                <div key={printer.id} className="flex flex-wrap items-center gap-3 py-3 first:pt-0 last:pb-0">
                  <Printer className="size-4 shrink-0 text-muted-foreground" />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-sm font-medium">{printer.name}</div>
                    <div className="truncate text-xs text-muted-foreground">
                      {PROTOCOLS[printer.protocol].name} · {printer.size} · <span className="font-mono">{printer.host}:{printer.port}</span>
                    </div>
                  </div>
                  <Button type="button" variant="outline" size="sm" disabled={!enabled} onClick={() => testPrint(printer)}>{t('Test print')}</Button>
                  <Button type="button" variant="outline" size="icon-sm" aria-label={t('Edit {name}', { name: printer.name })} onClick={() => setEditing({ printer, key: Date.now() })}>
                    <Pencil className="size-4" />
                  </Button>
                  <Button type="button" variant="outline" size="icon-sm" className="text-destructive" aria-label={t('Remove {name}', { name: printer.name })} onClick={() => setRemoving(printer)}>
                    <Trash2 className="size-4" />
                  </Button>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {editing && (
        <PrinterFormDialog
          key={editing.key}
          printer={editing.printer}
          media={media}
          open
          onOpenChange={(open) => !open && setEditing(null)}
        />
      )}

      <AlertDialog open={removing !== null} onOpenChange={(open) => !open && setRemoving(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t('Remove {name}?', { name: removing?.name ?? '' })}</AlertDialogTitle>
            <AlertDialogDescription>{t('Members won\'t be able to print on it any more. Labels already printed are not affected.')}</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t('Cancel')}</AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive text-white hover:bg-destructive/90"
              onClick={() => removing && router.delete(`/label_printers/${removing.id}`, { preserveScroll: true })}
            >
              {t('Remove')}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}
