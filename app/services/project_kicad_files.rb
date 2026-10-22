# frozen_string_literal: true

# Pulls the schematics out of a project's KiCad files, loose or zipped, and
# turns them into BOM lines (BomParser::KicadSchematic).
#
#   ProjectKicadFiles.bom_lines([ [ "board.zip", "/tmp/upload" ] ])
#   ProjectKicadFiles.bom_lines_for(project) # from its attached files
#
# Only *.kicad_sch files are read, each up to BomParser::MAX_FILE_SIZE and
# MAX_SCHEMATICS_SIZE in all; ZIP entries are read into memory, never written
# to disk, so archive paths don't matter. KiCad's autosaves and the
# "<project>-backups" folder are skipped.
module ProjectKicadFiles
  MAX_SCHEMATICS_SIZE = 50.megabytes
  MAX_ZIP_ENTRIES = 5_000

  # The files can't be read: an unreadable ZIP, a schematic over the limits, or
  # one that isn't a KiCad 6+ schematic. The message is shown to the user.
  class Unreadable < StandardError; end

  module_function

  # BOM lines from +files+, a list of [filename, path] pairs. Empty when the
  # files hold no schematic. Raises Unreadable.
  def bom_lines(files)
    BomParser::KicadSchematic.parse(schematics(files))
  rescue BomParser::KicadSchematic::NotASchematic => e
    raise Unreadable, I18n.t("errors.kicad_files.not_a_schematic", name: File.basename(e.message))
  end

  # Same, from the files attached to +project+.
  def bom_lines_for(project)
    opened = []
    files = project.kicad_files.map(&:blob).select { |blob| schematics?([ blob.filename.to_s ]) }.map do |blob|
      file = Tempfile.new([ "kicad", File.extname(blob.filename.to_s) ], binmode: true)
      opened << file
      blob.download { |chunk| file.write(chunk) }
      file.flush
      [ blob.filename.to_s, file.path ]
    end
    bom_lines(files)
  ensure
    opened.each(&:close!)
  end

  # Why +uploads+ (uploaded files) can't be attached to a project already
  # holding +existing+ files, or nil when they can.
  def upload_error(uploads, existing: 0)
    if (other = uploads.find { |upload| Project.kicad_content_type(upload.original_filename).nil? })
      I18n.t("errors.kicad_files.not_kicad", name: File.basename(other.original_filename.to_s))
    elsif uploads.size + existing > Project::MAX_KICAD_FILES
      I18n.t("errors.kicad_files.too_many", count: Project::MAX_KICAD_FILES)
    elsif (large = uploads.find { |upload| upload.size > Project::MAX_KICAD_FILE_SIZE })
      I18n.t("errors.kicad_files.too_large", name: File.basename(large.original_filename.to_s), size: ActiveSupport::NumberHelper.number_to_human_size(Project::MAX_KICAD_FILE_SIZE))
    end
  end

  # Attachables for has_many_attached, typed by name.
  def attachables(uploads)
    uploads.map do |upload|
      { io: File.open(upload.path, "rb"), filename: File.basename(upload.original_filename.to_s),
        content_type: Project.kicad_content_type(upload.original_filename) }
    end
  end

  # [filename, path] pairs for bom_lines.
  def upload_files(uploads)
    uploads.map { |upload| [ upload.original_filename.to_s, upload.path ] }
  end

  # Whether any of +filenames+ can hold a schematic (a .kicad_sch or a ZIP).
  def schematics?(filenames)
    filenames.any? { |name| schematic_name?(name) || File.extname(name.to_s).casecmp?(".zip") }
  end

  # A name for a project made from +filenames+: its .kicad_pro, else its first
  # schematic or archive.
  def project_name(filenames)
    name = filenames.find { |f| File.extname(f.to_s).casecmp?(".kicad_pro") } ||
      filenames.find { |f| schematic_name?(f) } || filenames.first
    File.basename(name.to_s, ".*").presence
  end

  # [name, text] for every schematic in +files+.
  def schematics(files)
    budget = { left: MAX_SCHEMATICS_SIZE }
    files.flat_map do |filename, path|
      if File.extname(filename.to_s).casecmp?(".zip")
        zip_schematics(filename, path, budget)
      elsif schematic_name?(filename)
        [ [ filename, read_schematic(filename, budget) { File.open(path, "rb") { |f| f.read(BomParser::MAX_FILE_SIZE + 1) } } ] ]
      else
        []
      end
    end
  end

  def zip_schematics(filename, path, budget)
    Zip::File.open(path) do |zip|
      raise Unreadable, I18n.t("errors.kicad_files.zip_too_many", name: filename) if zip.size > MAX_ZIP_ENTRIES

      zip.entries.select { |entry| entry.file? && schematic_name?(entry.name) }.sort_by(&:name).map do |entry|
        text = read_schematic(entry.name, budget) do
          entry.get_input_stream { |io| io.read(BomParser::MAX_FILE_SIZE + 1) }
        end
        [ entry.name, text ]
      end
    end
  rescue Zip::Error
    raise Unreadable, I18n.t("errors.kicad_files.not_a_zip", name: filename)
  end

  def read_schematic(name, budget)
    text = yield.to_s
    if text.bytesize > BomParser::MAX_FILE_SIZE || text.bytesize > budget[:left]
      raise Unreadable, I18n.t("errors.kicad_files.too_large_for_bom", name: File.basename(name))
    end

    budget[:left] -= text.bytesize
    text.force_encoding(Encoding::UTF_8).scrub
  end

  def schematic_name?(name)
    path = name.to_s
    base = File.basename(path)
    File.extname(base).casecmp?(".kicad_sch") && !base.start_with?("_autosave-", ".") &&
      path.split("/").none? { |dir| dir.end_with?("-backups") || dir == "__MACOSX" }
  end
end
