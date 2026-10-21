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
import { t, tx } from '@/lib/i18n'

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
  const target = mergeTargets.find((org) => String(org.id) === targetId)
  const orgName = <span className="font-medium text-foreground">{organization.name}</span>

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">{t('Danger zone')}</h2>
        <p className="max-w-xl text-sm text-muted-foreground">
          {t('Irreversible actions that affect the entire organization. Download a backup first if you may want the data back.')}
        </p>
      </div>

      <Card className="border-destructive/40">
        <CardHeader>
          <CardTitle>{t('Reset organization')}</CardTitle>
          <CardDescription>
            {tx('Deletes every part, zone, category, footprint, tag, supplier, stock movement, order and project of {name}. Settings, integrations and members are kept, and IPN numbering starts over.', { name: orgName })}
          </CardDescription>
        </CardHeader>
        <CardFooter className="justify-end gap-2 border-t border-destructive/40">
          <BackupButton />
          <ConfirmByNameDialog
            organization={organization}
            trigger={<><Eraser className="size-4" /> {t('Reset organization')}</>}
            title={t('Reset this organization?')}
            description={
              <>
                {tx('This permanently removes all inventory data of {name}. To confirm, type the organization name below.', { name: orgName })}
              </>
            }
            onConfirm={(confirmation) => router.post(`/organizations/${organization.id}/reset`, { confirmation })}
          />
        </CardFooter>
      </Card>

      {mergeTargets.length > 0 && (
        <Card className="border-destructive/40">
          <CardHeader>
            <CardTitle>{t('Merge into another organization')}</CardTitle>
            <CardDescription>
              {tx('Moves everything in {name} into an organization you own, then deletes this one. Categories, footprints, tags and suppliers with the same name are combined, parts with the same MPN, SKU or barcode become one part with the stock of both, and codes or IPNs already used there are renumbered. Members join with their role (owners as admins).', { name: orgName })}
            </CardDescription>
          </CardHeader>
          <CardFooter className="flex-wrap justify-end gap-2 border-t border-destructive/40">
            <Select value={targetId} onValueChange={setTargetId}>
              <SelectTrigger className="w-56" aria-label={t('Organization to merge into')}>
                <SelectValue placeholder={t('Merge into…')} />
              </SelectTrigger>
              <SelectContent>
                {mergeTargets.map((org) => (
                  <SelectItem key={org.id} value={String(org.id)}>{org.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <BackupButton />
            <ConfirmByNameDialog
              organization={organization}
              disabled={!target}
              trigger={<><GitMerge className="size-4" /> {t('Merge')}</>}
              title={t('Merge into {name}?', { name: target?.name ?? '' })}
              description={
                <>
                  {tx('All data of {name} moves into {target}, and {name} is deleted. To confirm, type its name below.', {
                    name: orgName,
                    target: <span className="font-medium text-foreground">{target?.name}</span>,
                  })}
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
          <CardTitle>{t('Delete organization')}</CardTitle>
          <CardDescription>
            {tx('Permanently deletes {name} and all of its parts, categories, stock movements, suppliers and members. This cannot be undone.', { name: orgName })}
          </CardDescription>
        </CardHeader>
        <CardFooter className="justify-end border-t border-destructive/40">
          <ConfirmByNameDialog
            organization={organization}
            trigger={<><Trash2 className="size-4" /> {t('Delete organization')}</>}
            title={t('Delete this organization?')}
            description={
              <>
                {tx('This permanently removes all data belonging to {name}. To confirm, type the organization name below.', { name: orgName })}
              </>
            }
            onConfirm={() => router.delete(`/organizations/${organization.id}`)}
          />
        </CardFooter>
      </Card>
      <div className="flex items-center gap-2 text-xs text-muted-foreground">
        <TriangleAlert className="size-3.5 shrink-0" />
        {t('You\'ll be switched to another organization after a merge or deletion.')}
      </div>
    </div>
  )
}

function BackupButton() {
  return (
    <Button asChild variant="outline">
      <a href="/backup/export" download>
        <Download className="size-4" /> {t('Download backup')}
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
          aria-label={t('Organization name')}
          autoFocus
        />
        <AlertDialogFooter>
          <AlertDialogCancel>{t('Cancel')}</AlertDialogCancel>
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
