import { Link, usePage, router } from '@inertiajs/react'
import { useEffect, useState } from 'react'
import { useTheme } from 'next-themes'
import {
  LayoutDashboard,
  List,
  Box,
  ScanLine,
  ArrowLeftRight,
  Truck,
  AlertTriangle,
  Users,
  Settings,
  ChevronUp,
  LogOut,
  User,
  ChevronsUpDown,
  Check,
  Plus,
  Sun,
  Moon,
} from 'lucide-react'

import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
} from '@/components/ui/sidebar'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { Button } from '@/components/ui/button'

const navigationItems = [
  { title: 'Dashboard', url: '/', icon: LayoutDashboard },
  { title: 'Inventory', url: '/parts', icon: List },
  { title: 'Storage Zones', url: '/storage_locations', icon: Box },
  { title: 'Scanner', url: '/scan', icon: ScanLine },
  { title: 'Movements', url: '/stock_movements', icon: ArrowLeftRight },
  { title: 'Suppliers', url: '/suppliers', icon: Truck },
  { title: 'Alerts', url: '/alerts', icon: AlertTriangle, badgeKey: 'alerts' as const },
  { title: 'Members & Roles', url: '/members', icon: Users },
  { title: 'Settings', url: '/settings', icon: Settings },
]

const ORG_BADGE_COLORS = [
  'bg-blue-600', 'bg-purple-600', 'bg-emerald-600', 'bg-amber-600', 'bg-pink-600', 'bg-cyan-600',
]

function ThemeToggle() {
  const { resolvedTheme, setTheme } = useTheme()
  const [mounted, setMounted] = useState(false)

  useEffect(() => setMounted(true), [])

  return (
    <Button
      variant="ghost"
      size="icon-sm"
      aria-label="Toggle theme"
      onClick={() => setTheme(resolvedTheme === 'dark' ? 'light' : 'dark')}
    >
      {mounted && resolvedTheme === 'light' ? <Moon /> : <Sun />}
    </Button>
  )
}

function initials(name: string) {
  const words = name.trim().split(/\s+/)
  return words.length === 1
    ? words[0].slice(0, 2).toUpperCase()
    : (words[0][0] + words[1][0]).toUpperCase()
}

interface Organization {
  id: number
  name: string
  member_count: number
}

interface UserInfo {
  email: string
  firstname: string
  lastname: string
}

interface PageProps {
  [key: string]: unknown
  auth?: {
    user?: UserInfo
    current_organization?: Organization
    organizations?: Organization[]
    alerts_count?: number
  }
}

export function AppSidebar() {
  const page = usePage<PageProps>()
  const { auth } = page.props
  const currentPath = page.url
  const user = auth?.user
  const currentOrganization = auth?.current_organization
  const organizations = auth?.organizations || []
  const alertsCount = auth?.alerts_count || 0

  const userDisplayName = user
    ? `${user.firstname} ${user.lastname}`.trim() || user.email.split('@')[0]
    : 'User'
  const userEmail = user?.email || ''
  const userInitials = user
    ? `${user.firstname?.[0] || ''}${user.lastname?.[0] || ''}`.toUpperCase() || user.email.slice(0, 2).toUpperCase()
    : 'U'

  const handleOrganizationSwitch = (orgId: number) => {
    router.post(`/organizations/${orgId}/switch`, {}, {
      preserveState: false,
      preserveScroll: true,
    })
  }

  return (
    <Sidebar>
      <SidebarHeader>
        <div className="flex items-center gap-2.5 px-2 pt-1 pb-2">
          <div className="flex size-7 items-center justify-center rounded-md bg-primary font-mono text-sm font-bold text-primary-foreground">
            Ω
          </div>
          <span className="text-sm font-semibold tracking-tight">Makerstorage</span>
        </div>

        <SidebarMenu>
          <SidebarMenuItem>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <SidebarMenuButton
                  size="lg"
                  className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
                >
                  <div
                    className={`flex aspect-square size-8 items-center justify-center rounded-md text-xs font-bold text-white ${currentOrganization ? ORG_BADGE_COLORS[currentOrganization.id % ORG_BADGE_COLORS.length] : 'bg-muted-foreground'}`}
                  >
                    {currentOrganization ? initials(currentOrganization.name) : '–'}
                  </div>
                  <div className="grid flex-1 text-left text-sm leading-tight">
                    <span className="truncate font-semibold">
                      {currentOrganization?.name || 'Select Organization'}
                    </span>
                    <span className="truncate text-xs text-muted-foreground">
                      {currentOrganization
                        ? `Team · ${currentOrganization.member_count} member${currentOrganization.member_count !== 1 ? 's' : ''}`
                        : 'No organization'}
                    </span>
                  </div>
                  <ChevronsUpDown className="ml-auto size-4" />
                </SidebarMenuButton>
              </DropdownMenuTrigger>
              <DropdownMenuContent
                className="w-[--radix-dropdown-menu-trigger-width] min-w-56 rounded-lg"
                align="start"
                sideOffset={4}
              >
                <DropdownMenuLabel className="text-xs text-muted-foreground">
                  Organizations
                </DropdownMenuLabel>
                {organizations.map((org) => (
                  <DropdownMenuItem
                    key={org.id}
                    onClick={() => handleOrganizationSwitch(org.id)}
                    className="cursor-pointer gap-2 p-2"
                  >
                    <div className={`flex size-6 items-center justify-center rounded-sm text-[10px] font-bold text-white ${ORG_BADGE_COLORS[org.id % ORG_BADGE_COLORS.length]}`}>
                      {initials(org.name)}
                    </div>
                    <span className="flex-1 truncate">{org.name}</span>
                    {currentOrganization?.id === org.id && (
                      <Check className="size-4 shrink-0" />
                    )}
                  </DropdownMenuItem>
                ))}
                <DropdownMenuSeparator />
                <DropdownMenuItem className="gap-2 p-2 cursor-pointer">
                  <div className="flex size-6 items-center justify-center rounded-md border bg-background">
                    <Plus className="size-4" />
                  </div>
                  <span className="text-muted-foreground">Create organization</span>
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>

      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupLabel>General</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {navigationItems.map((item) => (
                <SidebarMenuItem key={item.title}>
                  <SidebarMenuButton asChild tooltip={item.title} isActive={currentPath === item.url}>
                    <Link href={item.url}>
                      <item.icon />
                      <span>{item.title}</span>
                    </Link>
                  </SidebarMenuButton>
                  {item.badgeKey === 'alerts' && alertsCount > 0 && (
                    <SidebarMenuBadge className="bg-destructive/15 text-destructive">
                      {alertsCount}
                    </SidebarMenuBadge>
                  )}
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter>
        <SidebarMenu>
          <SidebarMenuItem className="flex items-center gap-2">
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <SidebarMenuButton
                  size="lg"
                  className="flex-1 data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
                >
                  <Avatar className="size-8">
                    <AvatarFallback>{userInitials}</AvatarFallback>
                  </Avatar>
                  <div className="grid flex-1 text-left text-sm leading-tight">
                    <span className="truncate font-semibold">{userDisplayName}</span>
                    <span className="truncate text-xs text-muted-foreground">{userEmail}</span>
                  </div>
                  <ChevronUp className="ml-auto size-4" />
                </SidebarMenuButton>
              </DropdownMenuTrigger>
              <DropdownMenuContent
                className="w-[--radix-dropdown-menu-trigger-width] min-w-56 rounded-lg"
                side="top"
                align="end"
                sideOffset={4}
              >
                <DropdownMenuItem asChild>
                  <Link href="/profile" className="cursor-pointer">
                    <User className="mr-2 size-4" />
                    Profile
                  </Link>
                </DropdownMenuItem>
                <DropdownMenuItem asChild>
                  <Link href="/settings" className="cursor-pointer">
                    <Settings className="mr-2 size-4" />
                    Settings
                  </Link>
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem asChild>
                  <Link href="/logout" method="delete" as="button" className="w-full cursor-pointer">
                    <LogOut className="mr-2 size-4" />
                    Log out
                  </Link>
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
            <ThemeToggle />
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  )
}
