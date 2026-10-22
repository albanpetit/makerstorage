import { useState } from 'react'
import { router } from '@inertiajs/react'
import { toast } from 'sonner'
import { Copy, Download, KeyRound, Library, Unplug } from 'lucide-react'

import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
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
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog'

import type { KicadSettings } from './types'

interface IssuedToken {
  token: string
  filename: string
  library_file: string
}

function csrfToken(): string {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ?? ''
}

function formatDate(value: string | null) {
  return value ? new Date(value).toLocaleString() : 'never'
}

function download(filename: string, content: string) {
  const url = URL.createObjectURL(new Blob([content], { type: 'application/json' }))
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  link.click()
  URL.revokeObjectURL(url)
}

// KiCad HTTP library (KicadLibrary): one token per organization, handed out
// once inside the .kicad_httplib file KiCad loads.
export function KicadSection({ kicad }: { kicad: KicadSettings }) {
  const [issued, setIssued] = useState<IssuedToken | null>(null)
  const [busy, setBusy] = useState(false)

  const issueToken = async () => {
    setBusy(true)
    try {
      const response = await fetch('/settings/kicad_token', {
        method: 'POST',
        headers: { Accept: 'application/json', 'X-CSRF-Token': csrfToken() },
      })
      if (!response.ok) throw new Error(String(response.status))
      const result: IssuedToken = await response.json()
      setIssued(result)
      download(result.filename, result.library_file)
      router.reload({ only: ['kicad'] })
    } catch {
      toast.error('Could not create the KiCad library token.')
    } finally {
      setBusy(false)
    }
  }

  const revoke = () => {
    setIssued(null)
    router.delete('/settings/kicad_token', { preserveScroll: true })
  }

  const copy = (text: string) => {
    navigator.clipboard?.writeText(text).then(() => toast.success('Copied to the clipboard.'))
  }

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">KiCad library</h2>
        <p className="max-w-xl text-sm text-muted-foreground">
          Browse your stocked parts in KiCad's symbol chooser and place them with their footprint, MPN, IPN and
          supplier already filled in. Needs KiCad 8 or later.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Library className="size-4" /> HTTP library
            {kicad.enabled ? <Badge variant="secondary">On</Badge> : <Badge variant="outline">Off</Badge>}
          </CardTitle>
          <CardDescription>
            {kicad.listed_parts_count} {kicad.listed_parts_count === 1 ? 'part is' : 'parts are'} available to KiCad.
            {kicad.parts_without_symbol_count > 0 && (
              <>
                {' '}{kicad.parts_without_symbol_count} more {kicad.parts_without_symbol_count === 1 ? 'has' : 'have'} no
                KiCad symbol yet: set one on their category (Categories page) or on the part itself.
              </>
            )}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4 text-sm">
          {kicad.enabled && (
            <div className="grid gap-1 text-muted-foreground">
              <div>Token created {formatDate(kicad.token_created_at)}</div>
              <div>Last used by KiCad {formatDate(kicad.token_last_used_at)}</div>
            </div>
          )}

          {issued && (
            <Alert>
              <KeyRound />
              <AlertTitle>Library file downloaded</AlertTitle>
              <AlertDescription className="space-y-2">
                <p>
                  {issued.filename} holds the token below, shown only now. In KiCad, open Preferences → Manage Symbol
                  Libraries, add it with the HTTP library type, and save it somewhere private: anyone with the file can
                  read your parts.
                </p>
                <div className="flex gap-2">
                  <Input readOnly value={issued.token} className="font-mono text-xs" onFocus={(e) => e.target.select()} />
                  <Button type="button" variant="outline" size="icon" onClick={() => copy(issued.token)} aria-label="Copy token">
                    <Copy className="size-4" />
                  </Button>
                  <Button
                    type="button"
                    variant="outline"
                    size="icon"
                    onClick={() => download(issued.filename, issued.library_file)}
                    aria-label="Download the library file again"
                  >
                    <Download className="size-4" />
                  </Button>
                </div>
              </AlertDescription>
            </Alert>
          )}

          <div className="space-y-1">
            <div className="text-xs font-medium text-muted-foreground">Root URL</div>
            <div className="flex gap-2">
              <Input readOnly value={kicad.root_url} className="font-mono text-xs" />
              <Button type="button" variant="outline" size="icon" onClick={() => copy(kicad.root_url)} aria-label="Copy root URL">
                <Copy className="size-4" />
              </Button>
            </div>
            <p className="text-xs text-muted-foreground">
              KiCad must reach this address: on another computer, use the server's LAN or public address rather than
              localhost.
            </p>
          </div>
        </CardContent>
        <CardFooter className="justify-end gap-2 border-t">
          {kicad.enabled && (
            <AlertDialog>
              <AlertDialogTrigger asChild>
                <Button type="button" variant="outline">
                  <Unplug className="size-4" /> Revoke
                </Button>
              </AlertDialogTrigger>
              <AlertDialogContent>
                <AlertDialogHeader>
                  <AlertDialogTitle>Revoke KiCad access?</AlertDialogTitle>
                  <AlertDialogDescription>
                    Every KiCad using the current library file stops seeing your parts. Symbols already placed in
                    schematics are not affected.
                  </AlertDialogDescription>
                </AlertDialogHeader>
                <AlertDialogFooter>
                  <AlertDialogCancel>Cancel</AlertDialogCancel>
                  <AlertDialogAction onClick={revoke}>Revoke</AlertDialogAction>
                </AlertDialogFooter>
              </AlertDialogContent>
            </AlertDialog>
          )}
          <Button type="button" onClick={issueToken} disabled={busy}>
            <Download className="size-4" />
            {kicad.enabled ? 'New library file' : 'Enable & download library file'}
          </Button>
        </CardFooter>
      </Card>

      {kicad.enabled && (
        <p className="text-xs text-muted-foreground">
          A new library file replaces the token: the previous file stops working.
        </p>
      )}
    </div>
  )
}
