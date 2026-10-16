# frozen_string_literal: true

module Oauth
  # OAuth token endpoint (authorization code with PKCE, refresh token) and
  # token revocation (RFC 7009) for MCP clients. Form-encoded, per RFC 6749.
  class TokensController < ActionController::API
    rate_limit to: 60, within: 1.minute, store: ApplicationController::AUTH_RATE_LIMIT_STORE,
               with: -> { render json: { error: "too_many_requests" }, status: :too_many_requests }

    before_action { response.headers["Cache-Control"] = "no-store" }

    def create
      client = OauthClient.find_by(uid: params[:client_id].to_s)
      return oauth_error("invalid_client", "Unknown client_id", status: :unauthorized) if client.nil?

      tokens =
        case params[:grant_type]
        when "authorization_code"
          OauthAuthorization.exchange_code!(
            client: client, code: params[:code].to_s, redirect_uri: params[:redirect_uri].to_s,
            code_verifier: params[:code_verifier].to_s
          )
        when "refresh_token"
          OauthAuthorization.refresh!(client: client, refresh_token: params[:refresh_token].to_s)
        else
          return oauth_error("unsupported_grant_type", "Use authorization_code or refresh_token")
        end

      render json: tokens.merge(token_type: "Bearer")
    rescue OauthAuthorization::InvalidGrant => e
      oauth_error("invalid_grant", e.message)
    end

    # Always answers 200, whether or not the token was known (RFC 7009 §2.2).
    def revoke
      token = params[:token].to_s
      if token.present?
        digest = OauthAuthorization.digest(token)
        OauthAuthorization.where(access_token_digest: digest).or(OauthAuthorization.where(refresh_token_digest: digest)).delete_all
      end
      head :ok
    end

    private

    def oauth_error(code, description, status: :bad_request)
      render json: { error: code, error_description: description }, status: status
    end
  end
end
