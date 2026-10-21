# frozen_string_literal: true

# Fetches a GitHub-linked project's KiCad files (Project#github_linked?) and
# refreshes its BOM from them.
#
#   ProjectGithubSync.call(project) # => ProjectGithubSync::Result
#
# The repository is downloaded at the commit its branch/tag points to now, and
# the KiCad files under the project's folder are kept, with their folders, as
# one ZIP attached to the project (blob metadata "github_sha" marks it; it
# replaces the previous one, while files added by hand stay). The BOM is read
# from the schematics in it and replaces the project's only when it changed,
# since replacing it sends the project back to draft (Project#replace_bom!).
# Nothing is downloaded when the commit is the one already fetched.
module ProjectGithubSync
  # The files can't be fetched or read; the message is shown to the user.
  class Error < StandardError; end

  # +status+ is :up_to_date or :updated; +bom+ is :unchanged, :replaced or
  # :empty (no schematic with components among the files).
  Result = Struct.new(:status, :sha, :file_count, :bom, :line_count, keyword_init: true)

  SNAPSHOT_KEY = "github_sha"

  module_function

  def call(project, force: false)
    raise Error, "This project isn't linked to a GitHub repository." unless project.github_linked?

    client = GithubClient.new(token: project.organization.github_token)
    sha = client.commit_sha(project.github_repository, project.github_ref)
    if !force && sha == project.github_synced_sha && snapshot_attachments(project).any?
      project.update!(github_synced_at: Time.current)
      return Result.new(status: :up_to_date, sha: sha)
    end

    client.download_archive(project.github_repository, sha) { |path| store(project, path, sha) }
  rescue GithubClient::Error, ProjectKicadFiles::Unreadable => e
    raise Error, e.message
  end

  # The attachments a sync made (as opposed to files added by hand).
  def snapshot_attachments(project)
    project.kicad_files.select { |file| snapshot?(file) }
  end

  def snapshot?(attachment)
    attachment.blob.metadata[SNAPSHOT_KEY].present?
  end

  def store(project, archive_path, sha)
    snapshot = Tempfile.new([ "github-kicad", ".zip" ], binmode: true)
    count = write_snapshot(project, archive_path, snapshot)
    if File.size(snapshot.path) > Project::MAX_KICAD_FILE_SIZE
      raise Error, "The KiCad files in #{project.github_location} are too large to keep (over #{ActiveSupport::NumberHelper.number_to_human_size(Project::MAX_KICAD_FILE_SIZE)} zipped)."
    end

    filename = "#{project.github_repository.split('/').last}-#{sha.first(7)}.zip"
    lines = ProjectKicadFiles.bom_lines([ [ filename, snapshot.path ] ])
    previous = snapshot_attachments(project)
    bom = lines.empty? ? :empty : (bom_changed?(project, lines) ? :replaced : :unchanged)

    ActiveRecord::Base.transaction do
      project.kicad_files.attach(
        io: StringIO.new(File.binread(snapshot.path)), filename: filename,
        content_type: Project::ZIP_TYPE, metadata: { SNAPSHOT_KEY => sha }
      )
      project.github_synced_sha = sha
      project.github_synced_at = Time.current
      project.save!
      project.replace_bom!(lines) if bom == :replaced
    end
    previous.each(&:purge)

    Result.new(status: :updated, sha: sha, file_count: count, bom: bom, line_count: lines.size)
  ensure
    snapshot&.close!
  end

  # Copies the KiCad files under the project's folder from the GitHub archive
  # (whose entries all sit in one "<owner>-<repo>-<sha>/" folder) into
  # +snapshot+, paths relative to that folder. Returns how many were copied.
  def write_snapshot(project, archive_path, snapshot)
    prefix = project.github_path.present? ? "#{project.github_path}/" : ""
    count = 0

    Zip::File.open(archive_path) do |archive|
      if archive.size > ProjectKicadFiles::MAX_ZIP_ENTRIES * 10
        raise Error, "#{project.github_repository} has too many files to read."
      end

      Zip::OutputStream.open(snapshot.path) do |out|
        archive.entries.sort_by(&:name).each do |entry|
          name = entry.name.split("/", 2).last.to_s
          next unless entry.file? && name.start_with?(prefix)

          relative = name.delete_prefix(prefix)
          next unless kicad_file?(relative)

          count += 1
          raise Error, "#{project.github_location} holds more than #{ProjectKicadFiles::MAX_ZIP_ENTRIES} KiCad files." if count > ProjectKicadFiles::MAX_ZIP_ENTRIES

          out.put_next_entry(relative)
          copied = entry.get_input_stream { |io| IO.copy_stream(io, out, Project::MAX_KICAD_FILE_SIZE + 1) }
          raise Error, "#{File.basename(relative)} is too large to keep." if copied > Project::MAX_KICAD_FILE_SIZE
        end
      end
    end
    raise Error, "No KiCad files in #{project.github_location}." if count.zero?

    count
  rescue Zip::Error
    raise Error, "Could not read the archive GitHub sent for #{project.github_repository}."
  end

  # KiCad files only (no nested ZIPs), leaving out KiCad's autosaves and
  # backup folders.
  def kicad_file?(path)
    base = File.basename(path)
    Project.kicad_content_type(path) == Project::KICAD_FILE_TYPE &&
      !base.start_with?("_autosave-", ".", "~") && !base.end_with?(".lck") &&
      path.split("/")[0...-1].none? { |dir| dir.end_with?("-backups") || dir.start_with?(".") }
  end

  # Whether +lines+ (parsed from the schematics) describe another BOM than the
  # project's current lines.
  def bom_changed?(project, lines)
    current = project.project_lines.map { |line| [ BomParser.line_key(line), line.quantity, line.designators.to_s ] }
    parsed = lines.map { |line| [ BomParser.line_key(line), line[:quantity], line[:designators].to_s ] }
    current.sort != parsed.sort
  end
end
