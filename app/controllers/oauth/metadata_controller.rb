# frozen_string_literal: true

module Oauth
  # Discovery documents MCP clients read before connecting: the protected
  # resource metadata (RFC 9728) pointing at this app as the authorization
  # server, and the authorization server metadata (RFC 8414).
  class MetadataController < ActionController::API
    include OauthUrls

    def protected_resource
      render json: {
        resource: mcp_resource_url,
        authorization_servers: [ oauth_issuer ],
        scopes_supported: SCOPES,
        bearer_methods_supported: [ "header" ],
        resource_name: "MakerStorage"
      }
    end

    def authorization_server
      render json: {
        issuer: oauth_issuer,
        authorization_endpoint: "#{oauth_issuer}/oauth/authorize",
        token_endpoint: "#{oauth_issuer}/oauth/token",
        registration_endpoint: "#{oauth_issuer}/oauth/register",
        revocation_endpoint: "#{oauth_issuer}/oauth/revoke",
        scopes_supported: SCOPES,
        response_types_supported: [ "code" ],
        response_modes_supported: [ "query" ],
        grant_types_supported: %w[authorization_code refresh_token],
        code_challenge_methods_supported: [ "S256" ],
        token_endpoint_auth_methods_supported: [ "none" ],
        revocation_endpoint_auth_methods_supported: [ "none" ],
        authorization_response_iss_parameter_supported: true
      }
    end
  end
end
