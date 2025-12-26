import { Link, usePage, router } from '@inertiajs/react'
import {
  Package,
  Tags,
  Layers,
  Truck,
  Footprints,
  Settings,
  ChevronUp,
  LogOut,
  User,
  Building2,
  ChevronsUpDown,
  Check,
  Plus,
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

const navigationItems = [
  {
    title: 'Parts',
    url: '/parts',
    icon: Package,
  },
  {
    title: 'Categories',
    url: '/categories',
    icon: Layers,
  },
  {
    title: 'Tags',
    url: '/tags',
    icon: Tags,
  },
  {
    title: 'Footprints',
    url: '/footprints',
    icon: Footprints,
  },
  {
    title: 'Suppliers',
    url: '/suppliers',
    icon: Truck,
  },
]

interface Organization {
  id: number
  name: string
}

interface UserInfo {
  email: string
  firstname: string
  lastname: string
}

interface PageProps {
  auth?: {
    user?: UserInfo
    current_organization?: Organization
    organizations?: Organization[]
  }
}

export function AppSidebar() {
  const { auth } = usePage<PageProps>().props
  const user = auth?.user
  const currentOrganization = auth?.current_organization
  const organizations = auth?.organizations || []

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
        <SidebarMenu>
          <SidebarMenuItem>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <SidebarMenuButton
                  size="lg"
                  className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
                >
                  <div className="flex aspect-square size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
                    <Building2 className="size-4" />
                  </div>
                  <div className="grid flex-1 text-left text-sm leading-tight">
                    <span className="truncate font-semibold">
                      {currentOrganization?.name || 'Select Organization'}
                    </span>
                    <span className="truncate text-xs text-muted-foreground">
                      {organizations.length} organization{organizations.length !== 1 ? 's' : ''}
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
                    <div className="flex size-6 items-center justify-center rounded-sm border">
                      <Building2 className="size-4 shrink-0" />
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
          <SidebarGroupLabel>Inventory</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {navigationItems.map((item) => (
                <SidebarMenuItem key={item.title}>
                  <SidebarMenuButton asChild tooltip={item.title}>
                    <Link href={item.url}>
                      <item.icon />
                      <span>{item.title}</span>
                    </Link>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>

        <SidebarGroup>
          <SidebarGroupLabel>Settings</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              <SidebarMenuItem>
                <SidebarMenuButton asChild tooltip="Settings">
                  <Link href="/settings">
                    <Settings />
                    <span>Settings</span>
                  </Link>
                </SidebarMenuButton>
              </SidebarMenuItem>
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter>
        <SidebarMenu>
          <SidebarMenuItem>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <SidebarMenuButton
                  size="lg"
                  className="data-[state=open]:bg-sidebar-accent data-[state=open]:text-sidebar-accent-foreground"
                >
                  <Avatar className="size-8 rounded-lg">
                    <AvatarFallback className="rounded-lg">{userInitials}</AvatarFallback>
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
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
    </Sidebar>
  )
}
