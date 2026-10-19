import { useState, type ReactNode } from 'react'
import { router } from '@inertiajs/react'
import { Download, Eraser, GitMerge, Trash2, TriangleAlert } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
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

import type { MergeTarget, OrganizationSettings } from './types'

// Owner-only actions on the whole organization (reset, merge, delete), each
// confirmed by typing the organization's name.
export function DangerSection({
  organization,
  mergeTargets,
}: {
  organization: OrganizationSettings
  mergeTargets: MergeTarget[]
}) {
  const [targetId, setTargetId] = useState('')
  const target = mergeTargets.find((t) => String(t.id) === targetId)

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">Danger zone</h2>
        <p className="max-w-xl text-sm text-muted-foreground">
          Irreversible actions that affect the entire organization. Download a backup first if you may want the data
          back.
        </p>
      </div>

      <Card className="border-destructive/40">
        <CardHeader>
          <CardTitle>Reset organization</CardTitle>
          <CardDescription>
            Deletes every part, zone, category, footprint, tag, supplier, stock movement, order and project of{' '}
            <span className="font-medium text-foreground">{organization.name}</span>. Settings, integrations and
            members are kept, and IPN numbering starts over.
          </CardDescription>
        </CardHeader>
        <CardFooter className="justify-end gap-2 border-t border-destructive/40">
          <BackupButton />
          <ConfirmByNameDialog
            organization={organization}
            trigger={<><Eraser className="size-4" /> Reset organization</>}
            title="Reset this organization?"
            description={
              <>
                This permanently removes all inventory data of{' '}
                <span className="font-medium text-foreground">{organization.name}</span>. To confirm, type the
                organization name below.
              </>
            }
            onConfirm={(confirmation) => router.post(`/organizations/${organization.id}/reset`, { confirmation })}
          />
        </CardFooter>
      </Card>

      {mergeTargets.length > 0 && (
        <Card className="border-destructive/40">
          <CardHeader>
            <CardTitle>Merge into another organization</CardTitle>
            <CardDescription>
              Moves everything in <span className="font-medium text-foreground">{organization.name}</span> into an
              organization you own, then deletes this one. Categories, footprints, tags and suppliers with the same
              name are combined, parts with the same MPN, SKU or barcode become one part with the stock of both, and
              codes or IPNs already used there are renumbered. Members join with their role (owners as admins).
            </CardDescription>
          </CardHeader>
          <CardFooter className="flex-wrap justify-end gap-2 border-t border-destructive/40">
            <Select value={targetId} onValueChange={setTargetId}>
              <SelectTrigger className="w-56" aria-label="Organization to merge into">
                <SelectValue placeholder="Merge into…" />
              </SelectTrigger>
              <SelectContent>
                {mergeTargets.map((t) => (
                  <SelectItem key={t.id} value={String(t.id)}>{t.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <BackupButton />
            <ConfirmByNameDialog
              organization={organization}
              disabled={!target}
              trigger={<><GitMerge className="size-4" /> Merge</>}
              title={`Merge into ${target?.name ?? ''}?`}
              description={
                <>
                  All data of <span className="font-medium text-foreground">{organization.name}</span> moves into{' '}
                  <span className="font-medium text-foreground">{target?.name}</span>, and{' '}
                  <span className="font-medium text-foreground">{organization.name}</span> is deleted. To confirm,
                  type its name below.
                </>
              }
              onConfirm={(confirmation) =>
                router.post(`/organizations/${organization.id}/merge`, { confirmation, target_id: target?.id })
              }
            />
          </CardFooter>
        </Card>
      )}

      <Card className="border-destructive/40">
        <CardHeader>
          <CardTitle>Delete organization</CardTitle>
          <CardDescription>
            Permanently deletes <span className="font-medium text-foreground">{organization.name}</span> and all of its
            parts, categories, stock movements, suppliers and members. This cannot be undone.
          </CardDescription>
        </CardHeader>
        <CardFooter className="justify-end border-t border-destructive/40">
          <ConfirmByNameDialog
            organization={organization}
            trigger={<><Trash2 className="size-4" /> Delete organization</>}
            title="Delete this organization?"
            description={
              <>
                This permanently removes all data belonging to{' '}
                <span className="font-medium text-foreground">{organization.name}</span>. To confirm, type the
                organization name below.
              </>
            }
            onConfirm={() => router.delete(`/organizations/${organization.id}`)}
          />
        </CardFooter>
      </Card>
      <div className="flex items-center gap-2 text-xs text-muted-foreground">
        <TriangleAlert className="size-3.5 shrink-0" />
        You'll be switched to another organization after a merge or deletion.
      </div>
    </div>
  )
}

function BackupButton() {
  return (
    <Button asChild variant="outline">
      <a href="/backup/export" download>
        <Download className="size-4" /> Download backup
      </a>
    </Button>
  )
}

// A destructive button whose dialog only confirms once the organization's
// name has been typed; the typed name is passed on for the server to check.
function ConfirmByNameDialog({
  organization,
  trigger,
  title,
  description,
  disabled = false,
  onConfirm,
}: {
  organization: OrganizationSettings
  trigger: ReactNode
  title: string
  description: ReactNode
  disabled?: boolean
  onConfirm: (confirmation: string) => void
}) {
  const [confirmation, setConfirmation] = useState('')

  return (
    <AlertDialog onOpenChange={() => setConfirmation('')}>
      <AlertDialogTrigger asChild>
        <Button type="button" variant="destructive" disabled={disabled}>
          {trigger}
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{title}</AlertDialogTitle>
          <AlertDialogDescription>{description}</AlertDialogDescription>
        </AlertDialogHeader>
        <Input
          value={confirmation}
          onChange={(e) => setConfirmation(e.target.value)}
          placeholder={organization.name}
          aria-label="Organization name"
          autoFocus
        />
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction
            disabled={confirmation.trim() !== organization.name.trim()}
            className="bg-destructive text-white hover:bg-destructive/90"
            onClick={() => onConfirm(confirmation)}
          >
            {trigger}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  )
}
