# frozen_string_literal: true

class DashboardController < ApplicationController
  include Auth

  before_action :verify_organization_access

  def index
    render inertia: "dashboard/index", props: DashboardSummary.new(current_organization).as_props
  end
end
