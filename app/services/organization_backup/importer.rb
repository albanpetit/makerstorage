module OrganizationBackup
  # Restores a backup archive (see OrganizationBackup) into a new organization
  # owned by +user+.
  #
  #   result = OrganizationBackup::Importer.new(path, user: current_user).import!
  #   result.organization   # the new organization
  #   result.skipped_files  # attachments left out (missing, too large, wrong type)
  #
  # Records are copied as they are in the file, timestamps included, with plain
  # INSERTs rather than through the models: a restore must reproduce the ledger
  # and the stock levels exactly, not replay them (a movement's callback would
  # credit the stock a second time, and order/IPN callbacks would renumber).
  # What the models would otherwise guarantee is checked here instead: every
  # reference resolves within the file, enumerated columns hold known values,
  # and the category and zone trees have no cycles. Database constraints
  # (NOT NULL, unique indexes, foreign keys) still apply.
  #
  # Raises OrganizationBackup::Error when the archive can't be restored; the
  # records are written in one transaction, so a failure leaves nothing behind.
  class Importer
    Result = Data.define(:organization, :records_count, :files_count, :skipped_files)

    def initialize(path, user:, name: nil)
      @path = path
      @user = user
      @name = name.to_s.strip.presence
    end

    def import!
      raise Error, "The file is larger than #{ActiveSupport::NumberHelper.number_to_human_size(MAX_ARCHIVE_SIZE)}." if File.size(@path) > MAX_ARCHIVE_SIZE

      Zip::File.open(@path) do |zip|
        raise Error, "The archive holds too many files." if zip.size > MAX_ENTRIES

        data = read_data(zip)
        organization, records_count = ActiveRecord::Base.transaction { restore_records(data) }
        files_count, skipped_files = restore_files(zip, data, organization)

        Result.new(organization: organization.reload, records_count: records_count, files_count: files_count, skipped_files: skipped_files)
      end
    rescue Zip::Error
      raise Error, "The file is not a valid backup archive."
    end

    private

    attr_reader :user

    def read_data(zip)
      entry = zip.find_entry(DATA_ENTRY)
      raise Error, "The archive has no #{DATA_ENTRY}: is it a MakerStorage backup?" unless entry
      raise Error, "#{DATA_ENTRY} is too large." if entry.size > MAX_DATA_SIZE

      data = JSON.parse(entry.get_input_stream.read)
      raise Error, "The archive is not a MakerStorage organization backup." unless data.is_a?(Hash) && data["format"] == FORMAT
      unless data["version"].is_a?(Integer) && data["version"].between?(1, VERSION)
        raise Error, "This backup was made by a newer version of MakerStorage (format #{data['version']}). Update this install first."
      end
      raise Error, "The backup has no organization data." unless data["organization"].is_a?(Hash) && data["tables"].is_a?(Hash)

      data
    rescue JSON::ParserError
      raise Error, "#{DATA_ENTRY} is not valid JSON."
    end

    # -- Records ---------------------------------------------------------------

    def restore_records(data)
      @ids = Hash.new { |hash, table| hash[table] = {} }
      organization = create_organization(data["organization"])
      count = 0

      TABLES.each do |table|
        rows = Array(data["tables"][table.name])
        rows.each do |row|
          raise Error, "#{table.name} holds an entry that isn't a record." unless row.is_a?(Hash)

          insert_row(table, row, organization)
        end
        restore_self_references(table, rows)
        count += rows.size
      end

      [ organization, count ]
    rescue ActiveRecord::RecordInvalid => e
      raise Error, "The organization settings are invalid: #{e.record.errors.full_messages.to_sentence}."
    rescue ActiveRecord::ActiveRecordError => e
      raise Error, "The backup could not be restored (#{e.class.name.demodulize}): its data is inconsistent."
    end

    def create_organization(attributes)
      organization = Organization.new(attributes.slice(*ORGANIZATION_ATTRIBUTES))
      organization.name = @name if @name
      organization.personal = false
      organization.save!
      organization.organization_memberships.create!(user: user, role: "owner")
      organization
    end

    def insert_row(table, row, organization)
      source_id = row["id"]
      raise Error, "A #{table.name.singularize.humanize(capitalize: false)} has no id." if source_id.nil?
      raise Error, "#{table.name} lists id #{source_id} twice." if @ids[table.name].key?(source_id)

      attributes = row.slice(*table.columns).except("id")
      table.references.each do |column, target|
        attributes[column] = target == table.name ? nil : resolve(table, column, target, attributes[column])
      end
      check_enums(table, attributes)
      attributes["organization_id"] = organization.id if table.model.column_names.include?("organization_id")

      # Catalog suppliers (Mouser, DigiKey) were seeded with the organization:
      # the backup's own record for that provider takes their place.
      if table.model == Supplier && attributes["catalog_provider"].present?
        seeded = organization.suppliers.find_by(catalog_provider: attributes["catalog_provider"])
        if seeded
          seeded.update_columns(cast(table, attributes).except("id", "organization_id"))
          return @ids[table.name][source_id] = seeded.id
        end
      end

      result = table.model.insert!(cast(table, attributes), returning: :id)
      @ids[table.name][source_id] = result.rows.first.first
    end

    # Runs the values through the model's attribute types, so dates, decimals
    # and booleans are stored the way the app writes them, and fills in the
    # column defaults for anything the file leaves out.
    def cast(table, attributes)
      now = Time.current
      record = table.model.new(attributes)
      record.created_at ||= now if record.has_attribute?(:created_at)
      record.updated_at ||= now if record.has_attribute?(:updated_at)
      record.attributes.except("id")
    end

    def resolve(table, column, target, source_id)
      return nil if source_id.nil?

      @ids[target].fetch(source_id) do
        raise Error, "A #{table.name.singularize.humanize(capitalize: false)} points at #{target.singularize.humanize(capitalize: false)} ##{source_id}, which isn't in the backup."
      end
    end

    def check_enums(table, attributes)
      table.enums.each do |column, allowed|
        value = attributes[column]
        next if value.blank? || allowed.include?(value)

        raise Error, "Unknown #{column.humanize(capitalize: false)} \"#{value}\" in #{table.name.humanize(capitalize: false)}."
      end
    end

    # Parents are linked once the whole table is in, since a tree's rows can
    # come in any order, and the result must stay a tree.
    def restore_self_references(table, rows)
      table.self_references.each do |column|
        parents = rows.each_with_object({}) do |row, links|
          next if row[column].nil?

          links[row["id"]] = row[column]
          resolve(table, column, table.name, row[column])
        end
        reject_cycles(table, parents)

        parents.each do |source_id, parent_source_id|
          table.model.where(id: @ids[table.name][source_id]).update_all(column => @ids[table.name][parent_source_id])
        end
      end
    end

    def reject_cycles(table, parents)
      safe = Set.new
      parents.each_key do |start|
        seen = Set.new
        node = start
        while node && !safe.include?(node)
          raise Error, "The #{table.name.humanize(capitalize: false)} tree loops back on itself." unless seen.add?(node)

          node = parents[node]
        end
        safe.merge(seen)
      end
    end

    # -- Files -----------------------------------------------------------------

    # Attached after the records are committed, one by one: a file that's
    # missing, too large or of the wrong type is skipped (and reported) rather
    # than failing the whole restore.
    def restore_files(zip, data, organization)
      restored = 0
      skipped = []

      Array(data["attachments"]).each do |entry|
        next unless entry.is_a?(Hash)

        if restore_file(zip, entry, organization)
          restored += 1
        else
          skipped << (entry["filename"].to_s.presence || entry["path"].to_s)
        end
      end

      [ restored, skipped ]
    end

    def restore_file(zip, entry, organization)
      table_name, name = entry.values_at("table", "name")
      limits = OrganizationBackup.attachment_limits_for(table_name.to_s)[name.to_s]
      return false unless limits

      record_type, record_id =
        if table_name == ORGANIZATION_TABLE
          [ "Organization", organization.id ]
        else
          [ TABLES_BY_NAME[table_name].model.name, @ids[table_name][entry["record_id"]] ]
        end
      return false unless record_id
      return false if single_attachment_taken?(record_type, record_id, name)

      file = zip.find_entry(entry["path"].to_s)
      return false if file.nil? || file.directory? || file.size > limits[:max_size]

      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(file.get_input_stream.read),
        filename: entry["filename"].to_s.presence || File.basename(file.name),
        content_type: entry["content_type"].presence
      )
      unless limits[:content_types].include?(blob.content_type) && blob.byte_size <= limits[:max_size]
        blob.purge
        return false
      end

      ActiveStorage::Attachment.create!(name: name, record_type: record_type, record_id: record_id, blob: blob)
      true
    rescue Zip::Error, ActiveRecord::ActiveRecordError, ActiveStorage::Error
      false
    end

    def single_attachment_taken?(record_type, record_id, name)
      reflection = record_type.constantize.reflect_on_attachment(name)
      reflection.macro == :has_one_attached &&
        ActiveStorage::Attachment.exists?(record_type: record_type, record_id: record_id, name: name)
    end
  end
end
