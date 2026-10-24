// Prop shapes for the Storage Zones page (StorageLocationsController#index).

export interface StorageLocationRecord {
  id: number
  name: string
  location_type: string
  code: string | null
  parent_id: number | null
  // A bag's number inside its box (null for other zones).
  position: number | null
}

export interface PartStorageEntry {
  location_id: number
  quantity: number
  part: {
    id: number
    reference: string
    name: string
    package_type: string | null
    unit: string
  }
}

export interface RecentMovement {
  location_id: number
  part_reference: string
  unit: string
  movement_type: 'in' | 'out' | 'adjustment'
  quantity_delta: number
  reason: string | null
  created_at: string
}

export interface StorageLocationsPageProps {
  storage_locations: StorageLocationRecord[]
  part_storages: PartStorageEntry[]
  recent_movements: RecentMovement[]
  // Zone to open on load (`?zone=ID`), already scoped to the organization.
  selected_zone_id: number | null
  bag_separator: string
}

export interface ZoneFormData {
  storage_location: {
    name: string
    location_type: string
    code: string
    parent_id: string
  }
}

export interface MoveRow {
  partId: number
  reference: string
  name: string
  quantity: number
  max: number
  unit: string
}

export interface MoveDialogState {
  // 'fixed' when the destination came from a drop; 'select' for the bulk button.
  mode: 'fixed' | 'select'
  fromId: number
  toId: number | null
  rows: MoveRow[]
}
