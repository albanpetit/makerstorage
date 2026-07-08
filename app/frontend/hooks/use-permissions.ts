import { usePage } from '@inertiajs/react'

export type OrganizationRole = 'owner' | 'admin' | 'member' | 'viewer'

interface AuthProps {
  [key: string]: unknown
  auth?: {
    is_organization_admin?: boolean
    is_organization_writer?: boolean
    organization_role?: OrganizationRole | null
  }
}

/**
 * Reads the current user's role in the active organization from the shared
 * Inertia `auth` prop. Mirrors the backend gates (`verify_organization_writer`
 * / `verify_organization_admin`) so the UI can hide actions the server would
 * reject anyway.
 */
export function usePermissions() {
  const { auth } = usePage<AuthProps>().props
  const role = auth?.organization_role ?? null
  const canWrite = auth?.is_organization_writer ?? false
  const canAdminister = auth?.is_organization_admin ?? false

  return {
    role,
    canWrite,
    canAdminister,
    isReadOnly: role != null && !canWrite,
  }
}
