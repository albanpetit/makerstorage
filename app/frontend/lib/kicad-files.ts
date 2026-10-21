// KiCad project files (and a zipped project folder) are attached to a project;
// keep in sync with Project::KICAD_EXTENSIONS / KICAD_FILENAMES.
export const KICAD_FILE = /(\.kicad_(pro|sch|pcb|sym|mod|prl|dru|wks)|\.zip|(^|[\\/])(sym|fp)-lib-table)$/i

export const KICAD_ACCEPT = '.kicad_pro,.kicad_sch,.kicad_pcb,.kicad_sym,.kicad_mod,.kicad_prl,.kicad_dru,.kicad_wks,.zip,application/zip'

export function formatFileSize(bytes: number) {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}
