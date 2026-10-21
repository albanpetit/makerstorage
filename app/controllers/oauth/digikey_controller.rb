# frozen_string_literal: true

module Oauth
  # 3-legged OAuth (Authorization Code) handshake that links a DigiKey customer
  # account to the current organization, so the user-scoped Order Status API can
  # be called on its behalf. Plain full-page redirects — the browser leaves to
  # digikey.com and comes back — not Inertia visits.
  class DigikeyController < ApplicationController
    include Auth

    before_action :verify_organization_access
    before_action :verify_organization_admin

    def authorize
      unless current_organization.digikey_configured?
        redirect_to settings_path, alert: t("flash.oauth_digikey.add_your_digikey_client_id_and")
        return
      end

      state = SecureRandom.hex(24)
      session[:digikey_oauth_state] = state
      # The tokens belong to the organization that started the handshake, not
      # whichever one is current when DigiKey redirects back.
      session[:digikey_oauth_organization_id] = current_organization.id

      redirect_to SupplierCatalog::Digikey.authorize_url(
        client_id: current_organization.digikey_client_id,
        redirect_uri: oauth_digikey_callback_url,
        state: state
      ), allow_other_host: true
    end

    def callback
      expected = session.delete(:digikey_oauth_state)
      started_in = session.delete(:digikey_oauth_organization_id)

      if params[:error].present?
        redirect_to settings_path, alert: t("flash.oauth_digikey.digikey_authorization_was_cancelled")
        return
      end

      if expected.blank? || params[:state] != expected
        redirect_to settings_path, alert: t("flash.oauth_digikey.digikey_authorization_could_not_be_verified")
        return
      end

      if started_in != current_organization.id
        redirect_to settings_path, alert: t("flash.oauth_digikey.you_switched_organization_during_the_digikey")
        return
      end

      tokens = SupplierCatalog::Digikey.exchange_code(
        client_id: current_organization.digikey_client_id,
        client_secret: current_organization.digikey_client_secret,
        code: params[:code].to_s,
        redirect_uri: oauth_digikey_callback_url
      )

      current_organization.update!(
        digikey_access_token: tokens["access_token"],
        digikey_refresh_token: tokens["refresh_token"],
        digikey_token_expires_at: Time.current + tokens["expires_in"].to_i.seconds
      )

      redirect_to settings_path, notice: t("flash.oauth_digikey.digikey_account_connected")
    rescue SupplierCatalog::LookupError => e
      redirect_to settings_path, alert: e.message
    end

    def disconnect
      current_organization.update!(
        digikey_access_token: nil,
        digikey_refresh_token: nil,
        digikey_token_expires_at: nil
      )
      redirect_to settings_path, notice: t("flash.oauth_digikey.digikey_account_disconnected")
    end
  end
end
