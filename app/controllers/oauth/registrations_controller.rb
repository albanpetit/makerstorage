# frozen_string_literal: true

module Oauth
  # OAuth Dynamic Client Registration (RFC 7591): how claude.ai and Claude Code
  # get a client id before sending the user to the consent page. Registering
  # grants nothing by itself; every client is public (PKCE, no secret).
  class RegistrationsController < ActionController::API
    rate_limit to: 20, within: 1.hour, store: ApplicationController::AUTH_RATE_LIMIT_STORE,
               with: -> { render json: { error: "too_many_requests" }, status: :too_many_requests }

    def create
      metadata = params.to_unsafe_h
      client = OauthClient.new(
        name: metadata["client_name"].to_s.strip.first(100).presence || "MCP client",
        redirect_uris: Array(metadata["redirect_uris"])
      )

      if client.save
        render status: :created, json: {
          client_id: client.uid,
          client_id_issued_at: client.created_at.to_i,
          client_name: client.name,
          redirect_uris: client.redirect_uris,
          token_endpoint_auth_method: "none",
          grant_types: %w[authorization_code refresh_token],
          response_types: [ "code" ],
          scope: OauthAuthorization::SCOPE
        }
      else
        render status: :bad_request, json: {
          error: "invalid_redirect_uri",
          error_description: client.errors.full_messages.to_sentence
        }
      end
    end
  end
end
