require "./spec_helper"
require "base64"

private def mcp_post(body : String) : HTTP::Client::Response
  headers = HTTP::Headers{
    "Content-Type" => "application/json",
    "Accept"       => "application/json",
  }
  call_request_on_app(HTTP::Request.new("POST", "/mcp", headers, body))
end

private def rpc_request(method : String, params : String = "{}", id : Int32 = 1) : String
  %({"jsonrpc":"2.0","id":#{id},"method":#{method.to_json},"params":#{params}})
end

private def tool_call(name : String, arguments : String = "{}") : String
  rpc_request("tools/call", %({"name":#{name.to_json},"arguments":#{arguments}}))
end

describe "MCP server (/mcp)" do
  test_config = uninitialized AppConfig
  media_root  = uninitialized String
  cache_dir   = uninitialized String

  before_each do
    media_root = "/tmp/test-mcp-#{Random.new.hex(6)}"
    cache_dir  = "/tmp/test-mcp-cache-#{Random.new.hex(6)}"

    FileUtils.mkdir_p(File.join(media_root, "subdir"))
    FileUtils.mkdir_p(cache_dir)
    File.open(File.join(media_root, "photo.jpg"), "wb") { |f| f.write(JPEG_BYTES) }
    File.write(File.join(media_root, "video.mp4"), "A" * 100)

    test_config = AppConfig.from_yaml("media_root: #{media_root}\ncache_dir: #{cache_dir}")

    reset_kemal_state
    Kemal.config.logging = false
    AppRouter.setup(test_config)
  end

  after_each do
    reset_kemal_state
    FileUtils.rm_rf(media_root)
    FileUtils.rm_rf(cache_dir)
  end

  describe "initialize" do
    it "returns protocol version, capabilities and server info" do
      response = mcp_post(rpc_request("initialize", %({"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}})))
      response.status_code.should eq(200)
      json = JSON.parse(response.body)
      json["jsonrpc"].as_s.should eq("2.0")
      json["id"].as_i.should eq(1)
      json["result"]["protocolVersion"].as_s.should eq("2025-06-18")
      json["result"]["capabilities"]["tools"].as_h.should_not be_nil
      json["result"]["serverInfo"]["name"].as_s.should eq("smb-media-viewer")
      json["result"]["instructions"].as_s.should contain("/api/v1/")
    end

    it "falls back to the latest supported version for an unknown protocolVersion" do
      response = mcp_post(rpc_request("initialize", %({"protocolVersion":"1999-01-01"})))
      json = JSON.parse(response.body)
      json["result"]["protocolVersion"].as_s.should eq("2025-06-18")
    end
  end

  describe "notifications" do
    it "acknowledges notifications/initialized with 202 and no body" do
      response = mcp_post(%({"jsonrpc":"2.0","method":"notifications/initialized"}))
      response.status_code.should eq(202)
      response.body.should eq("")
    end
  end

  describe "ping" do
    it "returns an empty result" do
      response = mcp_post(rpc_request("ping"))
      JSON.parse(response.body)["result"].as_h.should be_empty
    end
  end

  describe "tools/list" do
    it "lists the three tools with input schemas" do
      response = mcp_post(rpc_request("tools/list"))
      response.status_code.should eq(200)
      tools = JSON.parse(response.body)["result"]["tools"].as_a
      names = tools.map(&.["name"].as_s)
      names.should eq(["list_files", "get_file_info", "read_file"])
      tools.each { |t| t["inputSchema"]["type"].as_s.should eq("object") }
    end
  end

  describe "tools/call list_files" do
    it "returns entries with pagination info as structuredContent" do
      response = mcp_post(tool_call("list_files", %({"path":""})))
      json   = JSON.parse(response.body)
      result = json["result"]
      result["isError"].as_bool.should be_false
      sc = result["structuredContent"]
      sc["total"].as_i.should eq(3)
      sc["entries"].as_a.map(&.["name"].as_s).should contain("photo.jpg")
      # text content mirrors the structured payload
      JSON.parse(result["content"][0]["text"].as_s)["total"].as_i.should eq(3)
    end

    it "respects offset and limit arguments" do
      response = mcp_post(tool_call("list_files", %({"offset":1,"limit":1})))
      sc = JSON.parse(response.body)["result"]["structuredContent"]
      sc["entries"].as_a.size.should eq(1)
      sc["total"].as_i.should eq(3)
    end

    it "rejects path traversal with a tool error" do
      response = mcp_post(tool_call("list_files", %({"path":"../../etc"})))
      result = JSON.parse(response.body)["result"]
      result["isError"].as_bool.should be_true
      result["content"][0]["text"].as_s.should contain("invalid path")
    end

    it "reports a missing directory as a tool error" do
      response = mcp_post(tool_call("list_files", %({"path":"nonexistent"})))
      JSON.parse(response.body)["result"]["isError"].as_bool.should be_true
    end
  end

  describe "tools/call get_file_info" do
    it "returns detailed file info" do
      response = mcp_post(tool_call("get_file_info", %({"path":"photo.jpg"})))
      sc = JSON.parse(response.body)["result"]["structuredContent"]
      sc["name"].as_s.should eq("photo.jpg")
      sc["media_type"].as_s.should eq("image")
      sc["content_type"].as_s.should eq("image/jpeg")
      sc["size"].as_i64.should eq(JPEG_BYTES.size.to_i64)
    end

    it "requires the path argument" do
      response = mcp_post(tool_call("get_file_info"))
      result = JSON.parse(response.body)["result"]
      result["isError"].as_bool.should be_true
      result["content"][0]["text"].as_s.should contain("path")
    end
  end

  describe "tools/call read_file" do
    it "returns an image as base64 MCP image content" do
      response = mcp_post(tool_call("read_file", %({"path":"photo.jpg"})))
      content = JSON.parse(response.body)["result"]["content"][0]
      content["type"].as_s.should eq("image")
      content["mimeType"].as_s.should eq("image/jpeg")
      Base64.decode(content["data"].as_s).size.should eq(JPEG_BYTES.size)
    end

    it "returns a non-image file as an embedded base64 resource" do
      response = mcp_post(tool_call("read_file", %({"path":"video.mp4"})))
      content = JSON.parse(response.body)["result"]["content"][0]
      content["type"].as_s.should eq("resource")
      content["resource"]["mimeType"].as_s.should eq("video/mp4")
      String.new(Base64.decode(content["resource"]["blob"].as_s)).should eq("A" * 100)
    end

    it "rejects files above the size cap and points to the REST endpoint" do
      File.write(File.join(media_root, "big.mp4"), "A" * (11 * 1024 * 1024))
      response = mcp_post(tool_call("read_file", %({"path":"big.mp4"})))
      result = JSON.parse(response.body)["result"]
      result["isError"].as_bool.should be_true
      result["content"][0]["text"].as_s.should contain("/api/v1/content/")
    end

    it "rejects a directory path with a tool error" do
      response = mcp_post(tool_call("read_file", %({"path":"subdir"})))
      JSON.parse(response.body)["result"]["isError"].as_bool.should be_true
    end
  end

  describe "protocol errors" do
    it "returns -32601 for an unknown method" do
      response = mcp_post(rpc_request("resources/list"))
      JSON.parse(response.body)["error"]["code"].as_i.should eq(-32601)
    end

    it "returns -32602 for an unknown tool" do
      response = mcp_post(tool_call("delete_file", %({"path":"photo.jpg"})))
      JSON.parse(response.body)["error"]["code"].as_i.should eq(-32602)
    end

    it "returns -32700 with HTTP 400 for malformed JSON" do
      response = mcp_post("{not json")
      response.status_code.should eq(400)
      JSON.parse(response.body)["error"]["code"].as_i.should eq(-32700)
    end

    it "returns -32600 with HTTP 400 for a non-object body" do
      response = mcp_post(%("just a string"))
      response.status_code.should eq(400)
      JSON.parse(response.body)["error"]["code"].as_i.should eq(-32600)
    end

    it "responds 405 to GET /mcp" do
      response = call_request_on_app(HTTP::Request.new("GET", "/mcp"))
      response.status_code.should eq(405)
      response.headers["Allow"].should eq("POST")
    end

    it "responds 405 to DELETE /mcp" do
      response = call_request_on_app(HTTP::Request.new("DELETE", "/mcp"))
      response.status_code.should eq(405)
    end
  end
end
