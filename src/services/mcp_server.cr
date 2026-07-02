require "json"
require "base64"
require "uri"
require "../config"
require "./mime"
require "./file_browser"
require "./file_details"

# Minimal stateless MCP (Model Context Protocol) server.
#
# Implements the Streamable HTTP transport in its stateless form: every
# request is a single JSON-RPC 2.0 message POSTed to /mcp and answered with
# a plain JSON body (no SSE streams, no session management). This is enough
# for MCP clients (Claude, openclaw, ...) to discover and call the tools.
#
# Supported methods : initialize, ping, tools/list, tools/call
# Tools             : list_files, get_file_info, read_file
module McpServer
  PROTOCOL_VERSION            = "2025-06-18"
  SUPPORTED_PROTOCOL_VERSIONS = {"2024-11-05", "2025-03-26", "2025-06-18"}
  SERVER_NAME    = "smb-media-viewer"
  SERVER_VERSION = "0.1.0"

  # read_file refuses files larger than this; clients must stream large
  # files from GET /api/v1/content/*path instead.
  MAX_READ_BYTES = 10_i64 * 1024 * 1024

  INSTRUCTIONS = "Browse media files (images, videos, PDFs) stored on a Samba share. " \
                 "Use list_files to explore directories, get_file_info for metadata " \
                 "(including AI generation parameters embedded in PNG files), and " \
                 "read_file to fetch small files inline. Files larger than 10 MiB must " \
                 "be fetched over plain HTTP from GET /api/v1/content/<path> on this " \
                 "same host. The equivalent REST endpoints are GET /api/v1/list/<path>, " \
                 "GET /api/v1/info/<path> and GET /api/v1/content/<path>. All paths are " \
                 "relative to the media root; an empty string means the root itself."

  TOOLS_JSON = <<-JSON
    [
      {
        "name": "list_files",
        "title": "List files",
        "description": "List directories and files under a path relative to the media root. Directories come first, then files; hidden files and unsupported types are omitted. Returns a JSON object with path, offset, limit, total and entries (name, path, is_dir, size, mtime, media_type). REST equivalent: GET /api/v1/list/<path>.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "path":   {"type": "string", "description": "Directory path relative to the media root. Empty or omitted = root."},
            "offset": {"type": "integer", "minimum": 0, "description": "Number of entries to skip (default 0)."},
            "limit":  {"type": "integer", "minimum": 1, "maximum": 100, "description": "Maximum entries to return (default 50, max 100)."},
            "sort":   {"type": "string", "enum": ["name", "ctime", "mtime"], "description": "Sort key (default name)."},
            "order":  {"type": "string", "enum": ["asc", "desc"], "description": "Sort direction (default asc)."}
          }
        }
      },
      {
        "name": "get_file_info",
        "title": "Get file info",
        "description": "Get detailed metadata for a single file or directory: name, path, is_dir, size, mtime, media_type (image/video/pdf/directory/unknown), content_type, extension, and ai_metadata (AI generation parameters parsed from PNG tEXt/iTXt chunks, when present). REST equivalent: GET /api/v1/info/<path>.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "path": {"type": "string", "description": "File or directory path relative to the media root."}
          },
          "required": ["path"]
        }
      },
      {
        "name": "read_file",
        "title": "Read file",
        "description": "Fetch the raw bytes of a file. Images are returned as MCP image content; other types as an embedded base64 resource. Files larger than 10 MiB are rejected; fetch those via HTTP GET /api/v1/content/<path> instead (supports Range requests).",
        "inputSchema": {
          "type": "object",
          "properties": {
            "path": {"type": "string", "description": "File path relative to the media root."}
          },
          "required": ["path"]
        }
      }
    ]
    JSON

  record Response, status : Int32, body : String?

  # Handles one JSON-RPC message body and returns the HTTP status + JSON body.
  # A nil body means "no content" (202 Accepted for notifications).
  def self.handle(raw_body : String, config : AppConfig) : Response
    msg = begin
      JSON.parse(raw_body)
    rescue
      return Response.new(400, error_body(nil, -32700, "Parse error"))
    end

    obj = msg.as_h?
    return Response.new(400, error_body(nil, -32600, "Invalid Request")) unless obj

    method = obj["method"]?.try(&.as_s?)
    id     = obj["id"]?

    # Notifications (no id) are acknowledged with 202 and no body.
    return Response.new(202, nil) if id.nil?

    return Response.new(400, error_body(id, -32600, "Invalid Request")) unless method

    params = obj["params"]?.try(&.as_h?) || {} of String => JSON::Any

    body =
      case method
      when "initialize" then result_body(id, initialize_result(params))
      when "ping"       then result_body(id, "{}")
      when "tools/list" then result_body(id, %({"tools":#{TOOLS_JSON}}))
      when "tools/call" then handle_tools_call(id, params, config)
      else                   error_body(id, -32601, "Method not found: #{method}")
      end

    Response.new(200, body)
  end

  # --- JSON-RPC envelope helpers ---------------------------------------------

  private def self.result_body(id : JSON::Any, result_json : String) : String
    %({"jsonrpc":"2.0","id":#{id.to_json},"result":#{result_json}})
  end

  private def self.error_body(id : JSON::Any?, code : Int32, message : String) : String
    %({"jsonrpc":"2.0","id":#{id ? id.to_json : "null"},"error":{"code":#{code},"message":#{message.to_json}}})
  end

  # Tool execution failures are reported inside the result (isError: true),
  # not as JSON-RPC protocol errors — per the MCP specification.
  private def self.tool_error(id : JSON::Any, message : String) : String
    result_body(id, %({"content":[{"type":"text","text":#{message.to_json}}],"isError":true}))
  end

  # Wraps a JSON payload as both text content and structuredContent.
  private def self.structured_result(id : JSON::Any, payload_json : String) : String
    result_body(id, %({"content":[{"type":"text","text":#{payload_json.to_json}}],"structuredContent":#{payload_json},"isError":false}))
  end

  # --- Method handlers --------------------------------------------------------

  private def self.initialize_result(params : Hash(String, JSON::Any)) : String
    requested = params["protocolVersion"]?.try(&.as_s?)
    version   = requested && SUPPORTED_PROTOCOL_VERSIONS.includes?(requested) ? requested : PROTOCOL_VERSION

    {
      protocolVersion: version,
      capabilities:    {tools: {listChanged: false}},
      serverInfo:      {name: SERVER_NAME, title: "SMB Media Viewer", version: SERVER_VERSION},
      instructions:    INSTRUCTIONS,
    }.to_json
  end

  private def self.handle_tools_call(id : JSON::Any, params : Hash(String, JSON::Any), config : AppConfig) : String
    name = params["name"]?.try(&.as_s?)
    args = params["arguments"]?.try(&.as_h?) || {} of String => JSON::Any

    case name
    when "list_files"    then tool_list_files(id, args, config)
    when "get_file_info" then tool_get_file_info(id, args, config)
    when "read_file"     then tool_read_file(id, args, config)
    else                      error_body(id, -32602, "Unknown tool: #{name}")
    end
  end

  # --- Tools ------------------------------------------------------------------

  private def self.tool_list_files(id : JSON::Any, args : Hash(String, JSON::Any), config : AppConfig) : String
    rel_path = args["path"]?.try(&.as_s?) || ""
    offset   = [args["offset"]?.try(&.as_i?) || 0, 0].max
    limit    = [[args["limit"]?.try(&.as_i?) || 50, 1].max, 100].min
    sort_key = FileBrowser.parse_sort_key(args["sort"]?.try(&.as_s?) || "")
    sort_dir = FileBrowser.parse_sort_dir(args["order"]?.try(&.as_s?) || "")

    abs_path = FileBrowser.safe_path(config.media_root, rel_path)
    return tool_error(id, "invalid path: #{rel_path}") if abs_path.nil?
    return tool_error(id, "directory not found: #{rel_path}") unless Dir.exists?(abs_path)

    entries, total = FileBrowser.list_entries_with_total(
      config.media_root, rel_path, offset, limit, sort_key, sort_dir
    ).not_nil! # safe_path already validated above

    payload = {path: rel_path, offset: offset, limit: limit, total: total, entries: entries}.to_json
    structured_result(id, payload)
  end

  private def self.tool_get_file_info(id : JSON::Any, args : Hash(String, JSON::Any), config : AppConfig) : String
    rel_path = args["path"]?.try(&.as_s?)
    return tool_error(id, "missing required argument: path") if rel_path.nil?

    abs_path = FileBrowser.safe_path(config.media_root, rel_path)
    return tool_error(id, "invalid path: #{rel_path}") if abs_path.nil?
    return tool_error(id, "not found: #{rel_path}") unless File.exists?(abs_path)

    structured_result(id, FileDetails.build(abs_path, rel_path).to_json)
  end

  private def self.tool_read_file(id : JSON::Any, args : Hash(String, JSON::Any), config : AppConfig) : String
    rel_path = args["path"]?.try(&.as_s?)
    return tool_error(id, "missing required argument: path") if rel_path.nil?

    abs_path = FileBrowser.safe_path(config.media_root, rel_path)
    return tool_error(id, "invalid path: #{rel_path}") if abs_path.nil?
    return tool_error(id, "not found: #{rel_path}") unless File.exists?(abs_path)
    return tool_error(id, "not a file: #{rel_path}") unless File.file?(abs_path)

    size = File.size(abs_path)
    if size > MAX_READ_BYTES
      return tool_error(id, "file too large (#{size} bytes > #{MAX_READ_BYTES}); " \
                            "fetch it via HTTP: GET /api/v1/content/#{URI.encode_path(rel_path)}")
    end

    data = Base64.strict_encode(File.read(abs_path))
    mime = MimeService.content_type(File.basename(rel_path))

    # Raster images go out as MCP image content; SVG and everything else as an
    # embedded base64 resource (SVG is XML text, not decodable image data).
    result =
      if MimeService.media_type(File.basename(rel_path)).image? && mime != "image/svg+xml"
        %({"content":[{"type":"image","data":"#{data}","mimeType":"#{mime}"}],"isError":false})
      else
        %({"content":[{"type":"resource","resource":{"uri":"media:///#{URI.encode_path(rel_path)}","mimeType":"#{mime}","blob":"#{data}"}}],"isError":false})
      end
    result_body(id, result)
  end
end
