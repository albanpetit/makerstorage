require "csv"

module OrganizationBackup
  # Builds the backup archive of one organization (see OrganizationBackup).
  #
  #   OrganizationBackup::Exporter.new(organization).write_to(path) # writes the archive to a file
  #   OrganizationBackup::Exporter.new(organization).to_zip         # => binary String
  #
  # Attached files can weigh hundreds of MB in all, so the download goes
  # through #write_to: each file is streamed into the archive on disk, chunk by
  # chunk, instead of the whole archive being held in memory.
  class Exporter
    def initialize(organization)
      @organization = organization
    end

    def write_to(path)
      Zip::OutputStream.open(path) { |zip| write_entries(zip) }
      path
    end

    def to_zip
      Zip::OutputStream.write_buffer { |zip| write_entries(zip) }.string
    end

    private

    attr_reader :organization

    def write_entries(zip)
      tables = TABLES.to_h { |table| [ table.name, rows_for(table) ] }
      attachments = attachment_entries

      zip.put_next_entry(DATA_ENTRY)
      zip.write(JSON.generate(data(tables, attachments)))

      TABLES.each do |table|
        zip.put_next_entry("csv/#{table.name}.csv")
        zip.write(csv_for(table, tables[table.name]))
      end

      attachments.each do |entry|
        zip.put_next_entry(entry[:path])
        entry[:attachment].blob.download { |chunk| zip.write(chunk) }
      end
    end

    def data(tables, attachments)
      {
        format: FORMAT,
        version: VERSION,
        exported_at: Time.current.iso8601,
        schema_version: ActiveRecord::Base.connection_pool.migration_context.current_version,
        organization: organization.attributes.slice(*ORGANIZATION_ATTRIBUTES),
        tables: tables,
        attachments: attachments.map { |entry| entry.except(:attachment) }
      }.as_json
    end

    def rows_for(table)
      table.scope.call(organization).order(:id).pluck(*table.columns).map do |values|
        table.columns.zip(values).to_h
      end
    end

    def csv_for(table, rows)
      CSV.generate do |csv|
        csv << table.columns
        rows.each { |row| csv << row.values_at(*table.columns) }
      end
    end

    # The organization's logo, then every table's attachments, each with the
    # zip path its file is stored under.
    def attachment_entries
      owners = [ [ ORGANIZATION_TABLE, Organization, [ organization.id ] ] ]
      TABLES.each do |table|
        next if table.attachment_limits.empty?

        owners << [ table.name, table.model, table.scope.call(organization).select(:id) ]
      end

      owners.flat_map do |table_name, model, ids|
        ActiveStorage::Attachment
          .where(record_type: model.name, record_id: ids, name: OrganizationBackup.attachment_limits_for(table_name).keys)
          .includes(:blob).order(:id)
          .map do |attachment|
            {
              table: table_name,
              record_id: attachment.record_id,
              name: attachment.name,
              path: "files/#{attachment.id}/#{attachment.blob.filename.sanitized}",
              filename: attachment.blob.filename.to_s,
              content_type: attachment.blob.content_type,
              attachment: attachment
            }
          end
      end
    end
  end
end
