import { Eye } from 'lucide-react'

import { usePermissions } from '@/hooks/use-permissions'

/**
 * Renders a "Read only" pill when the current user's role cannot write in the
 * active organization. Renders nothing otherwise, so it can be dropped into any
 * header unconditionally.
 */
export function ReadOnlyBadge() {
  const { isReadOnly } = usePermissions()

  if (!isReadOnly) return null

  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-medium text-muted-foreground"
      title="Your role is read-only for this organization"
    >
      <Eye className="size-3.5" />
      Read only
    </span>
  )
}
