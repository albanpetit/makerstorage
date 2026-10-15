# frozen_string_literal: true

module Oauth
  # The OAuth consent page an MCP client (claude.ai, Claude Code…) sends the
  # user to: they sign in if needed, pick the organization to share, and allow
  # read-only access. Allowing sends an authorization code back to the client's
  # redirect URI, which the client trades for tokens at Oauth::TokensController.
  class AuthorizationsController < ApplicationController
    include Auth
    include OauthUrls

    before_action :load_client
    before_action :validate_request

    def new
      render inertia: "oauth/authorize", props: {
        client_name: @client.name,
        redirect_host: redirect_host,
        loopback: OauthClient.loopback_host?(URI.parse(@redirect_uri).host),
        mcp_url: mcp_resource_url,
        organizations: current_user.organizations.order(:name).map { |org| { id: org.id, name: org.name } },
        default_organization_id: current_organization&.id,
        request: request_params
      }
    end

    def create
      return redirect_to_client(error: "access_denied") unless params[:decision] == "allow"

      organization = current_user.organizations.find_by(id: params[:organization_id])
      if organization.nil?
        redirect_to oauth_authorize_path(request_params), alert: "Choose one of your organizations."
        return
      end

      code = OauthAuthorization.grant!(
        client: @client, user: current_user, organization: organization,
        redirect_uri: @redirect_uri, code_challenge: params[:code_challenge]
      )
      redirect_to_client(code: code)
    end

    private

    # An unknown client or unregistered redirect URI is shown here, never
    # redirected to: sending the user to an unverified URI would make this an
    # open redirector (RFC 6749 §4.1.2.1).
    def load_client
      @client = OauthClient.find_by(uid: params[:client_id].to_s)
      @redirect_uri = params[:redirect_uri].to_s
      return if @client&.redirect_uri_allowed?(@redirect_uri)

      render inertia: "oauth/authorize", status: :bad_request, props: {
        error: @client ? "This application asked to send you back to an address it never registered." : "This application isn't registered with MakerStorage. Add the connector again from your client."
      }
    end

    # The remaining errors can safely go back to the (verified) client.
    def validate_request
      if params[:response_type] != "code"
        redirect_to_client(error: "unsupported_response_type")
      elsif params[:code_challenge].blank? || params[:code_challenge_method] != "S256"
        redirect_to_client(error: "invalid_request", error_description: "PKCE with S256 is required")
      elsif current_user.organizations.none?
        redirect_to profile_path, alert: "You're not an active member of any organization."
      end
    end

    def request_params
      params.permit(:client_id, :redirect_uri, :response_type, :code_challenge, :code_challenge_method, :state, :scope, :resource).to_h
    end

    def redirect_host
      URI.parse(@redirect_uri).host
    end

    # Back to the client with the result, carrying its state and our issuer
    # (RFC 9207). Inertia visits can't follow a cross-origin redirect, so they
    # get a location visit instead.
    def redirect_to_client(**result)
      uri = URI.parse(@redirect_uri)
      query = URI.decode_www_form(uri.query.to_s)
      query.concat(result.map { |key, value| [ key.to_s, value ] })
      query << [ "state", params[:state].to_s ] if params[:state].present?
      query << [ "iss", oauth_issuer ]
      uri.query = URI.encode_www_form(query)

      if request.inertia?
        inertia_location(uri.to_s)
      else
        redirect_to uri.to_s, allow_other_host: true
      end
    end
  end
end
