require "kemal"
require "json"
require "uri"
require "./config"
require "./services/mime"
require "./services/file_browser"
require "./services/file_details"
require "./services/mcp_server"

# REST API (v1) for machine clients on the local network (e.g. openclaw),
# plus the MCP endpoint.
#
#   GET  /api/v1/list/         → root directory listing (JSON, paginated)
#   GET  /api/v1/list/*path    → directory listing (JSON, paginated)
#   GET  /api/v1/info/         → details of the media root
#   GET  /api/v1/info/*path    → file/directory details (JSON)
#   GET  /api/v1/content/*path → file body (correct Content-Type, Range supported)
#   POST /mcp                  → MCP server (JSON-RPC 2.0, stateless Streamable HTTP)
#
# Errors are returned as JSON: {"error": "<message>"} with 400/404/405 status.
module ApiRoutes
  def self.setup(config : AppConfig)
    get "/api/v1/list/" do |env|
      render_list(env, config, "")
    end

    get "/api/v1/list/*path" do |env|
      render_list(env, config, URI.decode(env.params.url["path"]))
    end

    get "/api/v1/info/" do |env|
      render_info(env, config, "")
    end

    get "/api/v1/info/*path" do |env|
      render_info(env, config, URI.decode(env.params.url["path"]))
    end

    get "/api/v1/content/*path" do |env|
      rel_path = URI.decode(env.params.url["path"])
      abs_path = FileBrowser.safe_path(config.media_root, rel_path)
      next error_response(env, 400, "invalid path") if abs_path.nil?
      next error_response(env, 404, "file not found") unless File.file?(abs_path)

      send_file(env, abs_path, MimeService.content_type(File.basename(rel_path)))
    end

    # MCP over Streamable HTTP, stateless form: plain JSON responses only —
    # no SSE stream to resume (GET) and no session to delete (DELETE).
    post "/mcp" do |env|
      body   = env.request.body.try(&.gets_to_end) || ""
      result = McpServer.handle(body, config)
      env.response.status_code = result.status
      if response_body = result.body
        env.response.content_type = "application/json"
        response_body
      else
        ""
      end
    end

    get "/mcp" do |env|
      env.response.headers["Allow"] = "POST"
      error_response(env, 405, "method not allowed: this MCP server is stateless, use POST")
    end

    delete "/mcp" do |env|
      env.response.headers["Allow"] = "POST"
      error_response(env, 405, "method not allowed: this MCP server is stateless, use POST")
    end
  end

  private def self.error_response(env : HTTP::Server::Context, status : Int32, message : String) : String
    env.response.status_code  = status
    env.response.content_type = "application/json"
    {error: message}.to_json
  end

  private def self.render_list(env : HTTP::Server::Context, config : AppConfig, rel_path : String) : String
    abs_path = FileBrowser.safe_path(config.media_root, rel_path)
    return error_response(env, 400, "invalid path") if abs_path.nil?
    return error_response(env, 404, "directory not found") unless Dir.exists?(abs_path)

    offset   = [env.params.query["offset"]?.try(&.to_i?) || 0, 0].max
    limit    = [[env.params.query["limit"]?.try(&.to_i?) || config.items_per_page, 1].max, 100].min
    sort_key = FileBrowser.parse_sort_key(env.params.query["sort"]? || "")
    sort_dir = FileBrowser.parse_sort_dir(env.params.query["order"]? || "")

    entries, total = FileBrowser.list_entries_with_total(
      config.media_root, rel_path, offset, limit, sort_key, sort_dir
    ).not_nil! # safe_path already validated above

    env.response.content_type = "application/json"
    {path: rel_path, offset: offset, limit: limit, total: total, entries: entries}.to_json
  end

  private def self.render_info(env : HTTP::Server::Context, config : AppConfig, rel_path : String) : String
    abs_path = FileBrowser.safe_path(config.media_root, rel_path)
    return error_response(env, 400, "invalid path") if abs_path.nil?
    return error_response(env, 404, "not found") unless File.exists?(abs_path)

    env.response.content_type = "application/json"
    FileDetails.build(abs_path, rel_path).to_json
  end
end
