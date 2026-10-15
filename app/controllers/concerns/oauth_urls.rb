require "active_support/concern"

# URLs of the OAuth authorization server and MCP resource this app serves (see
# McpController). Built from the request so they follow the host each install
# is reached on (LAN address, public domain…).
module OauthUrls
  extend ActiveSupport::Concern

  SCOPES = [ OauthAuthorization::SCOPE ].freeze

  private

  def oauth_issuer
    request.base_url
  end

  def mcp_resource_url
    "#{request.base_url}/mcp"
  end

  def mcp_resource_metadata_url
    "#{request.base_url}/.well-known/oauth-protected-resource/mcp"
  end
end
