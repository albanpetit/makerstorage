import { router, usePage } from '@inertiajs/react'
import { useState } from 'react'
import { FlaskConical, Trash2 } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { usePermissions } from '@/hooks/use-permissions'
import { t } from '@/lib/i18n'

interface DemoBannerProps {
  [key: string]: unknown
  auth?: { current_organization?: { id: number; name: string; demo?: boolean } | null }
}

// Shown on every page of a demo organization (OrganizationDemo): it's sample
// data, deleted in one click when the owner is done looking around.
export function DemoBanner() {
  const { auth } = usePage<DemoBannerProps>().props
  const { isOwner } = usePermissions()
  const [deleting, setDeleting] = useState(false)
  const organization = auth?.current_organization
  if (!organization?.demo) return null

  const discard = () => {
    setDeleting(true)
    router.delete(`/organizations/${organization.id}`, { onFinish: () => setDeleting(false) })
  }

  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-2 border-b bg-amber-50 px-4 py-2 text-sm text-amber-900 dark:bg-amber-950/40 dark:text-amber-200">
      <FlaskConical className="size-4 shrink-0" />
      <p className="min-w-0 flex-1">
        {t('This is a demo organization filled with sample data. Try anything: nothing here is real.')}
      </p>
      {isOwner && (
        <Button type="button" size="sm" variant="outline" disabled={deleting} onClick={discard}>
          <Trash2 className="size-4" />
          {t('Delete the demo')}
        </Button>
      )}
    </div>
  )
}
