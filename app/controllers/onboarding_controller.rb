# frozen_string_literal: true

# Guided onboarding, from the dashboard: admins start a new organization from
# a template (OrganizationTemplate) or empty, and put the first steps away;
# anyone can open a demo organization (OrganizationDemo) to look around.
class OnboardingController < ApplicationController
  include Auth

  before_action :verify_organization_access, except: :demo
  before_action :verify_organization_admin, except: :demo
  # Building a demo writes a few hundred rows: a handful per hour is plenty.
  rate_limit to: DEMO_RATE_LIMIT = 5, within: 1.hour, only: :demo, by: -> { current_user.id }, store: AUTH_RATE_LIMIT_STORE,
             with: -> { redirect_back_or_to root_path, alert: t("flash.onboarding.too_many_demos") }

  def template
    key = params[:template].to_s
    return redirect_to(root_path, alert: t("flash.onboarding.unknown_template")) unless OrganizationTemplate::KEYS.include?(key)

    result = OrganizationTemplate.apply!(current_organization, key)
    redirect_to root_path, notice: t("flash.onboarding.template_applied",
                                     categories: result.categories, storage_locations: result.storage_locations)
  end

  def skip
    current_organization.update!(onboarding_template: Organization::NO_TEMPLATE) if current_organization.onboarding_template.nil?
    redirect_to root_path
  end

  def dismiss
    current_organization.update!(onboarding_dismissed_at: Time.current)
    redirect_to root_path
  end

  def demo
    organization = OrganizationDemo.open_for!(current_user)
    session[:current_organization_id] = organization.id
    redirect_to root_path, notice: t("flash.onboarding.demo_opened", organization_name: organization.name)
  end
end
