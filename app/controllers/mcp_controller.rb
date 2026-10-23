# frozen_string_literal: true

# The MCP endpoint (Streamable HTTP transport, stateless): Claude POSTs one
# JSON-RPC message per request with an OAuth bearer token and gets a JSON
# answer from McpServer, scoped to the organization the token was granted for.
# An unauthenticated call answers 401 with a pointer to the OAuth metadata,
# which is what starts the sign-in flow in Claude.
class McpController < ActionController::API
  include OauthUrls

  MAX_BODY_SIZE = 1.megabyte

  before_action :authenticate_bearer!, only: :create

  def create
    if request.content_length.to_i > MAX_BODY_SIZE
      return render json: McpServer.error_response(nil, McpServer::INVALID_REQUEST, "Request too large"), status: 413
    end

    message = JSON.parse(request.raw_post)
    if message.is_a?(Array)
      return render json: McpServer.error_response(nil, McpServer::INVALID_REQUEST, "Batched requests are not supported"), status: :bad_request
    end

    organization = @authorization.organization
    response = Time.use_zone(organization.timezone) do
      McpServer.new(
        organization: organization, base_url: request.base_url,
        user: @authorization.user, client_name: @authorization.oauth_client.name, write: @authorization.can_write?
      ).handle(message)
    end
    response ? render(json: response) : head(:accepted)
  rescue JSON::ParserError
    render json: McpServer.error_response(nil, McpServer::PARSE_ERROR, "Invalid JSON"), status: :bad_request
  end

  # No server-to-client stream and no sessions to end (stateless server).
  def method_not_allowed
    response.headers["Allow"] = "POST"
    head :method_not_allowed
  end

  private

  def authenticate_bearer!
    token = request.authorization.to_s[/\ABearer (.+)\z/, 1]
    @authorization = OauthAuthorization.authenticate(token)
    return if @authorization

    challenge = %(Bearer resource_metadata="#{mcp_resource_metadata_url}", scope="#{OauthAuthorization::SCOPE}")
    challenge += %(, error="invalid_token") if token.present?
    response.headers["WWW-Authenticate"] = challenge
    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
