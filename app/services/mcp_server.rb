# frozen_string_literal: true

# A Model Context Protocol server (https://modelcontextprotocol.io) over one
# organization's inventory, so Claude (claude.ai, Claude Desktop, Claude Code)
# can answer "do I have the parts for this?" from the real stock.
#
# Handles one JSON-RPC message at a time for McpController, which serves it
# over the Streamable HTTP transport in stateless mode (plain JSON responses,
# no sessions, no server-initiated messages). Every tool only sees the
# organization the OAuth grant is for (see OauthAuthorization). The read-only
# tools (Tools) are always there; the ones that change the inventory
# (WriteTools) only when the grant allows changes and the user may write.
class McpServer
  PROTOCOL_VERSIONS = %w[2025-11-25 2025-06-18 2025-03-26 2024-11-05].freeze

  # JSON-RPC 2.0 error codes.
  PARSE_ERROR = -32_700
  INVALID_REQUEST = -32_600
  METHOD_NOT_FOUND = -32_601
  INVALID_PARAMS = -32_602
  INTERNAL_ERROR = -32_603

  class InvalidParams < StandardError; end

  attr_reader :organization, :base_url, :user, :client_name

  # +user+ and +client_name+ sign what the write tools record; +write+ says
  # whether they're offered at all.
  def initialize(organization:, base_url:, user: nil, client_name: nil, write: false)
    @organization = organization
    @base_url = base_url
    @user = user
    @client_name = client_name
    @write = write
  end

  def write?
    @write
  end

  # Returns the JSON-RPC response for +message+ (a parsed JSON object), or nil
  # for a notification or a client response, which get no reply.
  def handle(message)
    unless message.is_a?(Hash) && message["jsonrpc"] == "2.0"
      return error_response(nil, INVALID_REQUEST, "Expected a JSON-RPC 2.0 message")
    end
    return nil unless message.key?("id") && message.key?("method")

    id = message["id"]
    params = message["params"].is_a?(Hash) ? message["params"] : {}

    case message["method"]
    when "initialize" then result_response(id, initialize_result(params))
    when "ping" then result_response(id, {})
    when "tools/list" then result_response(id, { tools: tool_definitions })
    when "tools/call" then result_response(id, call_tool(params))
    else error_response(id, METHOD_NOT_FOUND, "Method not found: #{message['method']}")
    end
  rescue InvalidParams => e
    error_response(id, INVALID_PARAMS, e.message)
  end

  def self.error_response(id, code, message)
    { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
  end

  private

  def initialize_result(params)
    requested = params["protocolVersion"]
    {
      protocolVersion: PROTOCOL_VERSIONS.include?(requested) ? requested : PROTOCOL_VERSIONS.first,
      capabilities: { tools: { listChanged: false } },
      serverInfo: { name: "makerstorage", title: "MakerStorage", version: "1.0.0" },
      instructions: instructions
    }
  end

  def tool_definitions
    write? ? Tools.definitions + WriteTools.definitions : Tools.definitions
  end

  def instructions
    write? ? "#{read_instructions} #{write_instructions}" : "#{read_instructions} Nothing here can change the inventory."
  end

  def read_instructions
    <<~TEXT.squish
      Access to the MakerStorage electronic parts inventory of the organization "#{organization.name}".
      Use it to check whether parts are in stock, where they are stored, and whether a project or a BOM can be built.
      Quantities: on_hand is the physical stock; available is on_hand minus what confirmed projects have reserved;
      incoming is what open purchase orders will bring. To judge compatibility, compare the part fields
      (value, footprint/package, tolerance, voltage_rating, power_rating, mpn) against the requirement:
      search_parts with value and package filters finds substitutes.
    TEXT
  end

  def write_instructions
    <<~TEXT.squish
      This connection may also change the inventory: record stock coming in or going out, move stock between
      storage locations, record a count, create or edit parts, and create projects from a BOM. Every change is
      written to the stock ledger or the part under the user's name and cannot be undone from here, so look the
      part and location up first, and ask the user to confirm before changing anything they did not explicitly ask for.
    TEXT
  end

  def call_tool(params)
    name = params["name"].to_s
    arguments = params["arguments"].is_a?(Hash) ? params["arguments"] : {}
    data =
      if Tools.names.include?(name)
        Tools.new(organization: organization, base_url: base_url).call(name, arguments)
      elsif WriteTools.names.include?(name)
        unless write?
          raise Tools::ToolError, "This connection is read-only. To let it change the inventory, turn on " \
                                  "\"Allow changes\" for it in MakerStorage (Profile → Claude & AI assistants)."
        end

        WriteTools.new(organization: organization, base_url: base_url, user: user, client_name: client_name).call(name, arguments)
      else
        raise InvalidParams, "Unknown tool: #{name}"
      end
    { content: [ { type: "text", text: JSON.pretty_generate(data) } ], structuredContent: data, isError: false }
  rescue Tools::ToolError => e
    # Tool failures (bad input, nothing found) go back to the model as a
    # result it can read and correct, not as a protocol error.
    { content: [ { type: "text", text: e.message } ], isError: true }
  end

  def result_response(id, result)
    { jsonrpc: "2.0", id: id, result: result }
  end

  def error_response(id, code, message)
    self.class.error_response(id, code, message)
  end
end
