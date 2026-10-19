import * as React from "react"
import { Popover as PopoverPrimitive } from "radix-ui"
import { Check, ChevronsUpDown, Plus, Search } from "lucide-react"

import { cn } from "@/lib/utils"

export interface ComboboxOption {
  value: string
  label: string
  // Muted secondary text (e.g. a category's parent path), searched too. Shown
  // while searching, or always when the list isn't indented by `depth`.
  description?: string
  // Extra search terms that aren't displayed (e.g. a short code).
  keywords?: string[]
  // Indentation level in the unfiltered list, for tree-shaped options.
  depth?: number
  // Text for the trigger when this option is selected (defaults to `label`).
  selectedLabel?: string
  // Shown before the label (e.g. a storage zone's type icon).
  icon?: React.ReactNode
  // Short muted text at the end of the row, always shown (e.g. a zone's code).
  hint?: string
}

interface ComboboxProps {
  options: ComboboxOption[]
  value: string
  onValueChange: (value: string) => void
  placeholder?: string
  searchPlaceholder?: string
  emptyText?: string
  className?: string
  contentClassName?: string
  disabled?: boolean
  id?: string
  // Adds a last row that hands the current query back (e.g. "Create …").
  onCreate?: (query: string) => void
  createLabel?: (query: string) => string
}

function matches(option: ComboboxOption, terms: string[]) {
  const haystack = [option.description, option.label, ...(option.keywords ?? [])]
    .filter(Boolean)
    .join(" ")
    .toLowerCase()
  return terms.every((term) => haystack.includes(term))
}

// A lightweight searchable select built on the Radix Popover primitive. Used
// where a plain `Select` would render an unwieldy flat list (e.g. timezones).
// Deliberately dependency-free (no `cmdk`) so it stays offline-installable.
// Arrow keys move through the results and Enter picks one.
function Combobox({
  options,
  value,
  onValueChange,
  placeholder = "Select…",
  searchPlaceholder = "Search…",
  emptyText = "No results.",
  className,
  contentClassName,
  disabled,
  id,
  onCreate,
  createLabel = (query) => (query ? `Create "${query}"` : "Create new…"),
}: ComboboxProps) {
  const [open, setOpen] = React.useState(false)
  const [query, setQuery] = React.useState("")
  const [active, setActive] = React.useState(0)
  const listRef = React.useRef<HTMLDivElement>(null)
  const listId = React.useId()

  const selected = options.find((o) => o.value === value)
  const searching = query.trim() !== ""

  const filtered = React.useMemo(() => {
    const terms = query.trim().toLowerCase().split(/\s+/).filter(Boolean)
    if (terms.length === 0) return options
    return options.filter((o) => matches(o, terms))
  }, [options, query])

  // No create row when the query names an existing option exactly. When
  // shown, it counts as the last navigable item.
  const showCreate =
    !!onCreate && !filtered.some((o) => o.label.toLowerCase() === query.trim().toLowerCase())
  const itemCount = filtered.length + (showCreate ? 1 : 0)

  // Reset the query each time the popover closes so it reopens clean, and
  // start keyboard navigation on the current value.
  React.useEffect(() => {
    if (!open) {
      setQuery("")
      return
    }
    const index = options.findIndex((o) => o.value === value)
    setActive(index >= 0 ? index : 0)
    // Only on open: later option changes shouldn't move the cursor.
  }, [open])

  React.useEffect(() => {
    listRef.current
      ?.querySelector(`[data-index="${active}"]`)
      ?.scrollIntoView({ block: "nearest" })
  }, [active, open])

  const pick = (index: number) => {
    if (index < filtered.length) {
      onValueChange(filtered[index].value)
      setOpen(false)
    } else if (showCreate && onCreate) {
      setOpen(false)
      onCreate(query.trim())
    }
  }

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (itemCount === 0) return
    if (e.key === "ArrowDown") {
      e.preventDefault()
      setActive((i) => (i + 1) % itemCount)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      setActive((i) => (i - 1 + itemCount) % itemCount)
    } else if (e.key === "Enter") {
      e.preventDefault()
      pick(Math.min(active, itemCount - 1))
    }
  }

  return (
    <PopoverPrimitive.Root open={open} onOpenChange={setOpen}>
      <PopoverPrimitive.Trigger
        id={id}
        disabled={disabled}
        data-slot="combobox-trigger"
        className={cn(
          "border-input focus-visible:border-ring focus-visible:ring-ring/50 dark:bg-input/30 dark:hover:bg-input/50 flex items-center justify-between gap-2 rounded-md border bg-transparent px-3 py-2 text-sm whitespace-nowrap shadow-xs transition-[color,box-shadow] outline-none focus-visible:ring-[3px] disabled:cursor-not-allowed disabled:opacity-50 h-9",
          !selected && "text-muted-foreground",
          className
        )}
      >
        <span className="line-clamp-1 text-left">
          {selected ? selected.selectedLabel ?? selected.label : placeholder}
        </span>
        <ChevronsUpDown className="size-4 shrink-0 opacity-50" />
      </PopoverPrimitive.Trigger>

      <PopoverPrimitive.Portal>
        <PopoverPrimitive.Content
          align="start"
          sideOffset={4}
          className={cn(
            "bg-popover text-popover-foreground z-50 w-[var(--radix-popover-trigger-width)] min-w-[12rem] overflow-hidden rounded-md border shadow-md",
            "data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95",
            contentClassName
          )}
        >
          <div className="flex items-center gap-2 border-b px-3">
            <Search className="size-4 shrink-0 opacity-50" />
            <input
              autoFocus
              value={query}
              onChange={(e) => {
                setQuery(e.target.value)
                setActive(0)
              }}
              onKeyDown={onKeyDown}
              placeholder={searchPlaceholder}
              role="combobox"
              aria-expanded={open}
              aria-controls={listId}
              aria-activedescendant={itemCount > 0 ? `${listId}-${active}` : undefined}
              className="placeholder:text-muted-foreground flex h-9 w-full bg-transparent py-2 text-sm outline-none"
            />
          </div>
          <div ref={listRef} id={listId} role="listbox" className="max-h-64 overflow-y-auto p-1">
            {filtered.length === 0 && (
              <div className="text-muted-foreground py-6 text-center text-sm">{emptyText}</div>
            )}
            {filtered.map((option, index) => {
              const indent = !searching && option.depth ? option.depth : 0
              const showDescription = option.description && (searching || option.depth === undefined)
              return (
                <button
                  key={option.value}
                  id={`${listId}-${index}`}
                  data-index={index}
                  type="button"
                  role="option"
                  aria-selected={option.value === value}
                  tabIndex={-1}
                  onClick={() => pick(index)}
                  onMouseMove={() => setActive(index)}
                  style={indent ? { paddingLeft: `${0.5 + indent * 1.25}rem` } : undefined}
                  className={cn(
                    "flex w-full cursor-pointer items-center gap-2 rounded-sm px-2 py-1.5 text-left text-sm outline-none",
                    index === active && "bg-accent text-accent-foreground",
                    option.value === value && index !== active && "bg-accent/50"
                  )}
                >
                  <Check className={cn("size-4 shrink-0", option.value === value ? "opacity-100" : "opacity-0")} />
                  {option.icon}
                  <span className="max-w-[70%] shrink-0 truncate">{option.label}</span>
                  {(showDescription || option.hint) && (
                    <span className="text-muted-foreground ml-auto flex min-w-0 items-center gap-2 text-xs">
                      {showDescription && <span className="min-w-0 truncate">{option.description}</span>}
                      {option.hint && <span className="shrink-0 font-mono">{option.hint}</span>}
                    </span>
                  )}
                </button>
              )
            })}
            {showCreate && (
              <button
                id={`${listId}-${filtered.length}`}
                data-index={filtered.length}
                type="button"
                role="option"
                aria-selected={false}
                tabIndex={-1}
                onClick={() => pick(filtered.length)}
                onMouseMove={() => setActive(filtered.length)}
                className={cn(
                  "text-muted-foreground flex w-full cursor-pointer items-center gap-2 rounded-sm px-2 py-1.5 text-left text-sm outline-none",
                  filtered.length > 0 && "mt-1 border-t pt-2",
                  active === filtered.length && "bg-accent text-accent-foreground"
                )}
              >
                <Plus className="size-4 shrink-0" />
                <span className="line-clamp-1">{createLabel(query.trim())}</span>
              </button>
            )}
          </div>
        </PopoverPrimitive.Content>
      </PopoverPrimitive.Portal>
    </PopoverPrimitive.Root>
  )
}

export { Combobox }
