# One line of an organization's activity log (Activity page, admins only):
# who created, changed or deleted what, and when. Most events are written by
# Auditable callbacks while a user is signed in (`Current.user`); bulk
# operations (CSV import, part and organization merges, resets, backups)
# silence those with `ActivityEvent.without_recording` and write one summary
# event with `ActivityEvent.record!` instead.
#
# `subject_type` / `subject_id` name the record without a polymorphic
# association, and `subject_label` keeps how it read at the time, so a deleted
# record still shows. `details` holds the changed attributes of an update as
# { "attribute" => [before, after] } (foreign keys under the association name,
# with the record's label; secrets as nil, i.e. "changed"), or the facts of a
# summary event.
class ActivityEvent < ApplicationRecord
  ACTIONS = %w[create update destroy import merge reset export restore].freeze
  # Longer text values are cut so one edit of a long description can't bloat the log.
  MAX_VALUE_LENGTH = 200

  belongs_to :organization
  belongs_to :user, optional: true

  validates :action, inclusion: { in: ACTIONS }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # Runs the block without writing Auditable events (nested calls included).
  def self.without_recording
    previous = Current.activity_suppressed
    Current.activity_suppressed = true
    yield
  ensure
    Current.activity_suppressed = previous
  end

  def self.recording?
    Current.user.present? && !Current.activity_suppressed
  end

  # Writes an event for the signed-in user, if any. +subject+ is the record the
  # event is about (optional for organization-wide events).
  def self.record!(organization, action, subject = nil, details: {})
    return unless Current.user

    create!(
      organization: organization,
      user: Current.user,
      user_name: Current.user.display_name,
      action: action,
      subject_type: subject&.class&.name,
      subject_id: subject&.id,
      subject_label: subject && label_for(subject),
      details: details
    )
  end

  def self.label_for(record)
    record.respond_to?(:activity_label) ? record.activity_label.to_s.truncate(MAX_VALUE_LENGTH) : "##{record.id}"
  end

  # A value as stored in +details+: JSON-friendly and short.
  def self.loggable_value(value)
    case value
    when String then value.truncate(MAX_VALUE_LENGTH)
    when BigDecimal then value.to_s("F").sub(/\.0\z/, "")
    when Date then value.iso8601
    when Time, DateTime, ActiveSupport::TimeWithZone then value.iso8601
    else value
    end
  end
end
