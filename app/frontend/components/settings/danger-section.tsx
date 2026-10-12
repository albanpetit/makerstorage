import { useState } from 'react'
import { router } from '@inertiajs/react'
import { Trash2, TriangleAlert } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card'
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

import type { OrganizationSettings } from './types'

// Owner-only organization deletion, confirmed by typing its name.
export function DangerSection({ organization }: { organization: OrganizationSettings }) {
  const [deleteConfirm, setDeleteConfirm] = useState('')

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">Danger zone</h2>
        <p className="max-w-xl text-sm text-muted-foreground">
          Irreversible actions that affect the entire organization.
        </p>
      </div>

      <Card className="border-destructive/40">
        <CardHeader>
          <CardTitle>Delete organization</CardTitle>
          <CardDescription>
            Permanently deletes <span className="font-medium text-foreground">{organization.name}</span> and all of its
            parts, categories, stock movements, suppliers and members. This cannot be undone.
          </CardDescription>
        </CardHeader>
        <CardFooter className="justify-end border-t border-destructive/40">
          <AlertDialog onOpenChange={() => setDeleteConfirm('')}>
            <AlertDialogTrigger asChild>
              <Button type="button" variant="destructive">
                <Trash2 className="size-4" /> Delete organization
              </Button>
            </AlertDialogTrigger>
            <AlertDialogContent>
              <AlertDialogHeader>
                <AlertDialogTitle>Delete this organization?</AlertDialogTitle>
                <AlertDialogDescription>
                  This permanently removes all data belonging to{' '}
                  <span className="font-medium text-foreground">{organization.name}</span>. To confirm, type the
                  organization name below.
                </AlertDialogDescription>
              </AlertDialogHeader>
              <Input
                value={deleteConfirm}
                onChange={(e) => setDeleteConfirm(e.target.value)}
                placeholder={organization.name}
                autoFocus
              />
              <AlertDialogFooter>
                <AlertDialogCancel>Cancel</AlertDialogCancel>
                <AlertDialogAction
                  disabled={deleteConfirm.trim() !== organization.name.trim()}
                  className="bg-destructive text-white hover:bg-destructive/90"
                  onClick={() => router.delete(`/organizations/${organization.id}`)}
                >
                  Delete organization
                </AlertDialogAction>
              </AlertDialogFooter>
            </AlertDialogContent>
          </AlertDialog>
        </CardFooter>
      </Card>
      <div className="flex items-center gap-2 text-xs text-muted-foreground">
        <TriangleAlert className="size-3.5 shrink-0" />
        You'll be switched to another organization after deletion.
      </div>
    </div>
  )
}
