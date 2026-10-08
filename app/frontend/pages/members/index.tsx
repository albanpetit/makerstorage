import { Head, router, useForm } from '@inertiajs/react'
import { FormEvent, useMemo, useState } from 'react'
import { Crown, Shield, Wrench, Eye, UserPlus, MoreHorizontal, Check, X } from 'lucide-react'

import { AppLayout } from '@/layouts/app-layout'
import { PageHeader } from '@/components/page-header'
import { FlashMessages } from '@/components/flash-messages'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Field, FieldContent, FieldError, FieldLabel } from '@/components/ui/field'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
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

type Role = 'owner' | 'admin' | 'member' | 'viewer'

interface Member {
  id: number
  name: string
  email: string
  role: Role
  active: boolean
  pending: boolean
  is_you: boolean
  joined_at: string
}

interface MembersPageProps {
  members: Member[]
}

const AVATAR_COLORS = [
  'bg-emerald-600', 'bg-blue-600', 'bg-purple-600', 'bg-pink-600', 'bg-cyan-600', 'bg-amber-600',
]

const ROLE_META: Record<Role, { label: string; icon: typeof Crown; className: string; description: string; permissions: string[] }> = {
  owner: {
    label: 'Owner', icon: Crown,
    className: 'bg-purple-100 text-purple-700 dark:bg-purple-950 dark:text-purple-400',
    description: 'Full control, including billing and the team itself.',
    permissions: [ 'Manage members & roles', 'Configure organization settings', 'Create / delete anything', 'Record stock movements' ],
  },
  admin: {
    label: 'Admin', icon: Shield,
    className: 'bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-400',
    description: 'Manages inventory, zones, and day-to-day operations.',
    permissions: [ 'Manage members & roles', 'Create / edit components', 'Record stock movements', 'Manage storage zones' ],
  },
  member: {
    label: 'Member', icon: Wrench,
    className: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-400',
    description: 'Everyday inventory and stock movement access.',
    permissions: [ 'Create / edit components', 'Record stock movements', 'Scan & count stock', 'Cannot manage members' ],
  },
  viewer: {
    label: 'Viewer', icon: Eye,
    className: 'bg-muted text-muted-foreground',
    description: 'Read-only access for consulting and exporting data.',
    permissions: [ 'View components & zones', 'Export data', 'Cannot edit inventory', 'Cannot manage members' ],
  },
}

const ROLE_ORDER: Role[] = [ 'owner', 'admin', 'member', 'viewer' ]

function initials(name: string) {
  const words = name.trim().split(/\s+/)
  return words.length === 1
    ? words[0].slice(0, 2).toUpperCase()
    : (words[0][0] + words[1][0]).toUpperCase()
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, { day: '2-digit', month: '2-digit', year: 'numeric' })
}

interface InviteFormData {
  member: {
    email: string
    role: Role
  }
}

export default function MembersIndex({ members }: MembersPageProps) {
  const [inviteOpen, setInviteOpen] = useState(false)
  const [removeTarget, setRemoveTarget] = useState<Member | null>(null)

  const inviteForm = useForm<InviteFormData>({ member: { email: '', role: 'member' } })

  const openInviteDialog = () => {
    inviteForm.reset()
    inviteForm.clearErrors()
    setInviteOpen(true)
  }

  const submitInvite = (e: FormEvent) => {
    e.preventDefault()
    inviteForm.post('/members', {
      preserveScroll: true,
      onSuccess: () => setInviteOpen(false),
    })
  }

  const changeRole = (member: Member, role: Role) => {
    if (role === member.role) return
    router.patch(`/members/${member.id}`, { member: { role } }, { preserveScroll: true })
  }

  const confirmRemove = () => {
    if (!removeTarget) return
    router.delete(`/members/${removeTarget.id}`, {
      preserveScroll: true,
      onSuccess: () => setRemoveTarget(null),
    })
  }

  const stats = useMemo(() => {
    const countBy = (role: Role) => members.filter((m) => m.role === role).length
    return [
      { label: 'Members', value: String(members.length), className: '' },
      { label: 'Owners', value: String(countBy('owner')), className: 'text-purple-600 dark:text-purple-400' },
      { label: 'Admins', value: String(countBy('admin')), className: 'text-blue-600 dark:text-blue-400' },
      { label: 'Viewers', value: String(countBy('viewer')), className: '' },
    ]
  }, [members])

  const roleCards = useMemo(() => (
    ROLE_ORDER.map((role) => ({
      role,
      meta: ROLE_META[role],
      count: members.filter((m) => m.role === role).length,
    }))
  ), [members])

  return (
    <AppLayout
      header={
        <PageHeader title="Members & Roles" subtitle="Manage your team's access to the workshop">
          <Button size="sm" onClick={openInviteDialog}>
            <UserPlus className="size-4" />
            Invite Member
          </Button>
        </PageHeader>
      }
    >
      <Head title="Members & Roles" />

      <div className="space-y-6">
        <FlashMessages />

        {/* Stats */}
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          {stats.map((stat) => (
            <Card key={stat.label}>
              <CardContent>
                <div className="text-sm text-muted-foreground">{stat.label}</div>
                <div className={`mt-1 font-mono text-2xl font-bold ${stat.className}`}>{stat.value}</div>
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Members table */}
        <div>
          <h2 className="mb-2 text-sm font-semibold">
            Team members <span className="font-normal text-muted-foreground">· {members.length}</span>
          </h2>
          <Card className="gap-0 overflow-hidden py-0">
            <Table>
              <TableHeader>
                <TableRow className="bg-muted hover:bg-muted">
                  <TableHead className="py-2">Member</TableHead>
                  <TableHead className="py-2">Role</TableHead>
                  <TableHead className="py-2">Joined</TableHead>
                  <TableHead className="py-2">Status</TableHead>
                  <TableHead className="w-[60px] py-2 text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {members.map((member, i) => {
                  const meta = ROLE_META[member.role]
                  return (
                    <TableRow key={member.id}>
                      <TableCell className="py-2.5">
                        <div className="flex items-center gap-3">
                          <div className={`flex size-8 shrink-0 items-center justify-center rounded-full font-mono text-xs font-semibold text-white ${AVATAR_COLORS[i % AVATAR_COLORS.length]}`}>
                            {initials(member.name)}
                          </div>
                          <div className="min-w-0">
                            <div className="font-semibold">
                              {member.name}
                              {member.is_you && <span className="ml-1.5 text-xs font-normal text-muted-foreground">· you</span>}
                            </div>
                            <div className="font-mono text-xs text-muted-foreground">{member.email}</div>
                          </div>
                        </div>
                      </TableCell>
                      <TableCell className="py-2.5">
                        <Badge className={meta.className} variant="outline">
                          <meta.icon className="size-3" />
                          {meta.label}
                        </Badge>
                      </TableCell>
                      <TableCell className="py-2.5 text-sm text-muted-foreground">{formatDate(member.joined_at)}</TableCell>
                      <TableCell className="py-2.5">
                        {member.pending ? (
                          <span className="inline-flex items-center gap-1.5 text-sm text-muted-foreground">
                            <span className="size-1.5 rounded-full bg-amber-500" />
                            Invited
                          </span>
                        ) : (
                          <span className={`inline-flex items-center gap-1.5 text-sm ${member.active ? '' : 'text-muted-foreground'}`}>
                            <span className={`size-1.5 rounded-full ${member.active ? 'bg-emerald-500' : 'bg-muted-foreground'}`} />
                            {member.active ? 'Active' : 'Inactive'}
                          </span>
                        )}
                      </TableCell>
                      <TableCell className="py-2.5 text-right">
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild>
                            <Button variant="outline" size="icon-sm">
                              <MoreHorizontal className="size-4" />
                            </Button>
                          </DropdownMenuTrigger>
                          <DropdownMenuContent align="end">
                            <DropdownMenuLabel className="text-xs text-muted-foreground">Change role</DropdownMenuLabel>
                            {ROLE_ORDER.map((role) => {
                              const RoleIcon = ROLE_META[role].icon
                              return (
                                <DropdownMenuItem key={role} onClick={() => changeRole(member, role)} className="cursor-pointer justify-between">
                                  <span className="flex items-center gap-2">
                                    <RoleIcon className="size-3.5" />
                                    {ROLE_META[role].label}
                                  </span>
                                  {member.role === role && <Check className="size-3.5" />}
                                </DropdownMenuItem>
                              )
                            })}
                            <DropdownMenuSeparator />
                            <DropdownMenuItem
                              className="cursor-pointer text-destructive focus:text-destructive"
                              onClick={() => setRemoveTarget(member)}
                            >
                              <X className="mr-2 size-4" />
                              Remove from organization
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </Card>
        </div>

        {/* Roles reference */}
        <div>
          <h2 className="mb-2 text-sm font-semibold">Roles & permissions</h2>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {roleCards.map(({ role, meta, count }) => (
              <Card key={role}>
                <CardContent>
                  <div className="mb-2.5 flex items-center gap-2.5">
                    <span className={`flex size-8 shrink-0 items-center justify-center rounded-lg ${meta.className}`}>
                      <meta.icon className="size-4" />
                    </span>
                    <div>
                      <div className="font-semibold">{meta.label}</div>
                      <div className="font-mono text-xs text-muted-foreground">{count} member{count !== 1 ? 's' : ''}</div>
                    </div>
                  </div>
                  <ul className="flex flex-col gap-1.5">
                    {meta.permissions.map((perm) => (
                      <li key={perm} className="text-xs text-muted-foreground">{perm}</li>
                    ))}
                  </ul>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      </div>

      {/* Invite member dialog */}
      <Dialog open={inviteOpen} onOpenChange={setInviteOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Invite a member</DialogTitle>
            <DialogDescription>They need an existing Makerstorage account, and join once they accept the invitation from their profile.</DialogDescription>
          </DialogHeader>
          <form onSubmit={submitInvite} className="flex flex-col gap-4">
            <Field>
              <FieldLabel>
                <Label>Email address</Label>
              </FieldLabel>
              <FieldContent>
                <Input
                  type="email"
                  placeholder="firstname@workshop.io"
                  value={inviteForm.data.member.email}
                  onChange={(e) => inviteForm.setData('member', { ...inviteForm.data.member, email: e.target.value })}
                />
              </FieldContent>
              {inviteForm.errors['member.email'] && <FieldError>{inviteForm.errors['member.email']}</FieldError>}
            </Field>
            <Field>
              <FieldLabel>
                <Label>Assigned role</Label>
              </FieldLabel>
              <FieldContent>
                <div className="flex flex-col gap-2">
                  {ROLE_ORDER.map((role) => {
                    const meta = ROLE_META[role]
                    const on = inviteForm.data.member.role === role
                    return (
                      <button
                        key={role}
                        type="button"
                        onClick={() => inviteForm.setData('member', { ...inviteForm.data.member, role })}
                        className={`flex items-center gap-3 rounded-lg border-[1.5px] p-3 text-left transition-colors ${
                          on ? 'border-primary bg-accent' : 'border-border hover:bg-accent'
                        }`}
                      >
                        <meta.icon className="size-4 shrink-0" />
                        <div className="min-w-0 flex-1">
                          <div className="text-sm font-semibold">{meta.label}</div>
                          <div className="text-xs text-muted-foreground">{meta.description}</div>
                        </div>
                        {on && <Check className="size-4 shrink-0 text-primary" />}
                      </button>
                    )
                  })}
                </div>
              </FieldContent>
            </Field>
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setInviteOpen(false)}>Cancel</Button>
              <Button type="submit" disabled={inviteForm.processing || !inviteForm.data.member.email.includes('@')}>
                <UserPlus className="size-4" />
                Send invitation
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Remove confirmation */}
      <AlertDialog open={!!removeTarget} onOpenChange={(open) => !open && setRemoveTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove this member?</AlertDialogTitle>
            <AlertDialogDescription>
              <span className="font-semibold text-foreground">{removeTarget?.name}</span> will lose access to this organization.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={confirmRemove} className="bg-destructive text-white hover:bg-destructive/90">
              Remove
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </AppLayout>
  )
}
