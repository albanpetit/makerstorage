# frozen_string_literal: true

# The organization's activity log (ActivityEvent), newest first, for admins:
# who created, changed or deleted what. Filters by member, record type,
# action, or one record's history (subject_type + subject_id).
class ActivityController < ApplicationController
  include Auth

  before_action :verify_organization_access
  before_action :verify_organization_admin

  PAGE_SIZE = 50

  # Where a record of each type is shown. Parts open in the page's detail
  # sheet instead.
  SUBJECT_PATHS = {
    "Part" => ->(_) { nil },
    "Category" => ->(_) { "/categories" },
    "Footprint" => ->(_) { "/footprints" },
    "Tag" => ->(_) { "/tags" },
    "ParameterDefinition" => ->(_) { "/parameters" },
    "StorageLocation" => ->(id) { "/storage_locations?zone=#{id}" },
    "Supplier" => ->(_) { "/suppliers" },
    "Order" => ->(id) { "/orders/#{id}" },
    "Project" => ->(id) { "/projects/#{id}" },
    "Stocktake" => ->(id) { "/stocktakes/#{id}" },
    "Loan" => ->(id) { "/loans/#{id}" },
    "LabelPrinter" => ->(_) { "/settings" },
    "OrganizationMembership" => ->(_) { "/members" },
    "Organization" => ->(_) { "/settings" }
  }.freeze

  def index
    scope = filtered_scope
    total = scope.count
    page_count = [ (total.to_f / PAGE_SIZE).ceil, 1 ].max
    page = [ [ params[:page].to_i, 1 ].max, page_count ].min

    events = scope.includes(:user).newest_first.offset((page - 1) * PAGE_SIZE).limit(PAGE_SIZE).to_a
    existing = existing_subjects(events)

    render inertia: "activity/index", props: {
      events: events.map { |event| serialize_event(event, existing) },
      pagination: { page: page, page_count: page_count, total: total, page_size: PAGE_SIZE },
      filters: {
        user_id: params[:user_id].presence,
        subject_type: subject_type_filter,
        event_action: params[:event_action].presence_in(ActivityEvent::ACTIONS),
        subject_id: subject_type_filter && params[:subject_id].presence&.to_i,
        subject_label: subject_label_filter
      },
      users: users_with_events,
      subject_types: current_organization.activity_events.where.not(subject_type: nil).distinct.order(:subject_type).pluck(:subject_type)
    }
  end

  private

  def filtered_scope
    scope = current_organization.activity_events
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
    scope = scope.where(subject_type: subject_type_filter) if subject_type_filter
    scope = scope.where(subject_id: params[:subject_id]) if subject_type_filter && params[:subject_id].present?
    scope = scope.where(action: params[:event_action]) if params[:event_action].presence_in(ActivityEvent::ACTIONS)
    scope
  end

  def subject_type_filter
    params[:subject_type].presence_in(SUBJECT_PATHS.keys)
  end

  # The label of the record whose history is shown, from its latest event.
  def subject_label_filter
    return nil unless subject_type_filter && params[:subject_id].present?

    current_organization.activity_events.where(subject_type: subject_type_filter, subject_id: params[:subject_id])
      .newest_first.pick(:subject_label)
  end

  def users_with_events
    ids = current_organization.activity_events.where.not(user_id: nil).distinct.pluck(:user_id)
    User.where(id: ids).map { |user| { id: user.id, name: user.display_name } }.sort_by { |user| user[:name].downcase }
  end

  # type => ids of this page's subjects that still exist in the organization.
  def existing_subjects(events)
    events.select(&:subject_id).group_by(&:subject_type).to_h do |type, typed|
      ids = typed.map(&:subject_id).uniq
      found =
        if type == "Organization"
          ids & [ current_organization.id ]
        elsif SUBJECT_PATHS.key?(type)
          type.constantize.where(organization_id: current_organization.id, id: ids).pluck(:id)
        else
          []
        end
      [ type, found.to_set ]
    end
  end

  def serialize_event(event, existing)
    exists = event.subject_id.present? && existing.fetch(event.subject_type, Set.new).include?(event.subject_id)
    {
      id: event.id,
      created_at: event.created_at.iso8601,
      action: event.action,
      user_name: event.user&.display_name || event.user_name,
      subject_type: event.subject_type,
      subject_id: event.subject_id,
      subject_label: event.subject_label,
      subject_exists: exists,
      subject_url: exists ? SUBJECT_PATHS[event.subject_type]&.call(event.subject_id) : nil,
      details: event.details
    }
  end
end
