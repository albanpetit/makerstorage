# Writes an ActivityEvent when a record is created, updated or destroyed by a
# signed-in user (see ActivityEvent.recording?). A model opts in with
# `audited`:
#
#   audited ignore: %i[checked_at], secret: %i[api_key], on_create: %i[role]
#
#   ignore     attributes whose changes are bookkeeping, not worth an event
#              (an update changing nothing else writes none)
#   secret     attributes logged as "changed", without their values
#   on_create  attributes whose initial value the create event keeps
#   on         which of :create, :update, :destroy are logged
#
# Events are written in the record's own transaction, so a rolled-back change
# leaves no trace. Child rows (order lines, BOM lines, tags on a part…) are not
# audited on their own.
module Auditable
  extend ActiveSupport::Concern

  ALWAYS_IGNORED = %w[id organization_id created_at updated_at].freeze

  class_methods do
    def audited(ignore: [], secret: [], on_create: [], on: %i[create update destroy])
      class_attribute :audit_ignored, instance_writer: false, default: (ALWAYS_IGNORED + ignore.map(&:to_s)).freeze
      class_attribute :audit_secret, instance_writer: false, default: secret.map(&:to_s).freeze
      class_attribute :audit_on_create, instance_writer: false, default: on_create.map(&:to_s).freeze

      after_create -> { record_activity("create", audited_create_details) } if on.include?(:create)
      after_update -> { (changes = audited_changes).any? && record_activity("update", changes) } if on.include?(:update)
      after_destroy -> { record_activity("destroy") } if on.include?(:destroy)
    end
  end

  # How the record reads in the log. Models override it when their name alone
  # isn't the clearest (orders show their reference).
  def activity_label
    (try(:name).presence || try(:reference).presence || "##{id}").to_s
  end

  private

  def activity_organization
    is_a?(Organization) ? self : organization
  end

  def record_activity(action, details = {})
    return unless ActivityEvent.recording?

    ActivityEvent.record!(activity_organization, action, self, details: details)
  end

  def audited_create_details
    audit_on_create.each_with_object({}) do |attribute, details|
      value = self[attribute]
      details[attribute] = [ nil, ActivityEvent.loggable_value(value) ] if value.present?
    end
  end

  # { "attribute" => [before, after] } for this save, foreign keys resolved
  # to their record's label under the association name.
  def audited_changes
    saved_changes.except(*audit_ignored).each_with_object({}) do |(attribute, (before, after)), changes|
      if audit_secret.include?(attribute)
        changes[attribute] = nil
      elsif (reflection = audited_belongs_to[attribute])
        changes[reflection.name.to_s] = [ before, after ].map { |id| audited_label_of(reflection, id) }
      else
        changes[attribute] = [ before, after ].map { |value| ActivityEvent.loggable_value(value) }
      end
    end
  end

  def audited_belongs_to
    self.class.reflect_on_all_associations(:belongs_to)
      .reject { |reflection| reflection.polymorphic? || reflection.name == :organization }
      .index_by(&:foreign_key)
  end

  def audited_label_of(reflection, id)
    return nil if id.nil?

    record = reflection.klass.find_by(id: id)
    record ? ActivityEvent.label_for(record) : "##{id}"
  end
end
