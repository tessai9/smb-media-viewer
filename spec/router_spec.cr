require "spec"
require "file_utils"
require "json"

# Must be set BEFORE requiring src/app to suppress AppRouter.setup and Kemal.run
ENV["MEDIA_VIEWER_TEST"] = "1"

require "kemal"
require "../src/app"

# ---- Kemal test helpers (mirrors Kemal's own spec_helper pattern) ----

def call_request_on_app(request : HTTP::Request) : HTTP::Client::Response
  io       = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  context  = HTTP::Server::Context.new(request, response)
  main_handler = build_main_handler
  main_handler.call(context)
  response.close
  io.rewind
  HTTP::Client::Response.from_io(io, decompress: false)
end

def build_main_handler : HTTP::Handler
  Kemal.config.setup
  main_handler    = Kemal.config.handlers.first
  current_handler = main_handler
  Kemal.config.handlers.each do |handler|
    current_handler.next = handler
    current_handler = handler
  end
  main_handler
end

def reset_kemal_state
  Kemal.config.clear
  Kemal::FilterHandler::INSTANCE.tree =
    Radix::Tree(Array(Kemal::FilterHandler::FilterBlock)).new
  Kemal::RouteHandler::INSTANCE.routes =
    Radix::Tree(Kemal::Route).new
  Kemal::RouteHandler::INSTANCE.cached_routes =
    Kemal::LRUCache(String, Radix::Result(Kemal::Route)).new(Kemal.config.max_route_cache_size)
  Kemal::WebSocketHandler::INSTANCE.routes =
    Radix::Tree(Kemal::WebSocket).new
end

# Small valid JPEG (1×1 white pixel, minimal valid JFIF)
JPEG_BYTES = Bytes[
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
  0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
  0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
  0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
  0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
  0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
  0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
  0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
  0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
  0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03,
  0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D,
  0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06,
  0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
  0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72,
  0x82, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0xFB,
  0x26, 0xA5, 0xFF, 0xD9,
]

# ---- Tests ----

describe "HTTP Routes" do
  # test_config is set up fresh in each before_each
  test_config = uninitialized AppConfig
  media_root  = uninitialized String
  cache_dir   = uninitialized String

  before_each do
    # Create fresh temp directories for each test
    media_root = "/tmp/test-router-#{Random.new.hex(6)}"
    cache_dir  = "/tmp/test-cache-#{Random.new.hex(6)}"

    FileUtils.mkdir_p(media_root)
    FileUtils.mkdir_p(File.join(media_root, "subdir"))
    FileUtils.mkdir_p(cache_dir)

    # Write photo.jpg (valid minimal JPEG)
    File.open(File.join(media_root, "photo.jpg"), "wb") { |f| f.write(JPEG_BYTES) }
    # Write video.mp4 (100 bytes of 'A')
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

  # ----- 7.1: browse routes and JSON API -----

  describe "GET /" do
    it "redirects to /browse/ with 302" do
      request  = HTTP::Request.new("GET", "/")
      response = call_request_on_app(request)
      response.status_code.should eq(302)
      response.headers["Location"].should eq("/browse/")
    end
  end

  describe "GET /browse/" do
    it "returns 200 with HTML for the root directory" do
      request  = HTTP::Request.new("GET", "/browse/")
      response = call_request_on_app(request)
      response.status_code.should eq(200)
      response.body.should contain("<!DOCTYPE html>")
    end

    it "lists files from the media root" do
      request  = HTTP::Request.new("GET", "/browse/")
      response = call_request_on_app(request)
      response.body.should contain("photo.jpg")
    end
  end

  describe "GET /browse/*path" do
    it "returns 200 with HTML for a valid subdirectory" do
      request  = HTTP::Request.new("GET", "/browse/subdir")
      response = call_request_on_app(request)
      response.status_code.should eq(200)
      response.body.should contain("<!DOCTYPE html>")
    end

    it "returns 404 for a non-existent directory" do
      request  = HTTP::Request.new("GET", "/browse/nonexistent")
      response = call_request_on_app(request)
      response.status_code.should eq(404)
    end
  end

  describe "GET /api/files/" do
    it "returns 200 with a JSON array for the root directory" do
      request  = HTTP::Request.new("GET", "/api/files/")
      response = call_request_on_app(request)
      response.status_code.should eq(200)
      response.headers["Content-Type"].should contain("application/json")
      json = JSON.parse(response.body)
      json.as_a?.should_not be_nil
    end

    it "respects the limit query parameter" do
      request  = HTTP::Request.new("GET", "/api/files/?limit=1")
      response = call_request_on_app(request)
      json = JSON.parse(response.body)
      json.as_a.size.should be <= 1
    end

    it "respects the offset query parameter" do
      request  = HTTP::Request.new("GET", "/api/files/?offset=999")
      response = call_request_on_app(request)
      json = JSON.parse(response.body)
      json.as_a.size.should eq(0)
    end
  end

  describe "GET /api/files/*path" do
    it "returns 200 with a JSON array for a valid subdirectory" do
      request  = HTTP::Request.new("GET", "/api/files/subdir")
      response = call_request_on_app(request)
      response.status_code.should eq(200)
      json = JSON.parse(response.body)
      json.as_a?.should_not be_nil
    end

    it "returns 404 for a non-existent directory" do
      request  = HTTP::Request.new("GET", "/api/files/nonexistent")
      response = call_request_on_app(request)
      response.status_code.should eq(404)
    end
  end

  # ----- 7.2: viewer and raw file routes -----

  describe "GET /view/*path" do
    it "returns 200 HTML with <img> for an image file" do
      request  = HTTP::Request.new("GET", "/view/photo.jpg")
      response = call_request_on_app(request)
      response.status_code.should eq(200)
      response.body.should contain("<img")
      response.body.should contain("/raw/photo.jpg")
    end

    it "returns 404 for a non-existent file" do
      request  = HTTP::Request.new("GET", "/view/nonexistent.jpg")
      response = call_request_on_app(request)
      response.status_code.should eq(404)
    end
  end

  describe "GET /raw/*path" do
    it "returns 200 with correct Content-Type for an image" do
      request  = HTTP::Request.new("GET", "/raw/photo.jpg")
      response = call_request_on_app(request)
      response.status_code.should eq(200)
      response.headers["Content-Type"].should contain("image/jpeg")
    end

    it "includes Accept-Ranges: bytes header" do
      request  = HTTP::Request.new("GET", "/raw/video.mp4")
      response = call_request_on_app(request)
      response.headers["Accept-Ranges"].should eq("bytes")
    end

    it "returns 206 when Range header is present" do
      headers  = HTTP::Headers{"Range" => "bytes=0-9"}
      request  = HTTP::Request.new("GET", "/raw/video.mp4", headers)
      response = call_request_on_app(request)
      response.status_code.should eq(206)
    end

    it "includes Content-Range header for Range request" do
      headers  = HTTP::Headers{"Range" => "bytes=0-9"}
      request  = HTTP::Request.new("GET", "/raw/video.mp4", headers)
      response = call_request_on_app(request)
      response.headers["Content-Range"].should contain("bytes 0-9/100")
    end

    it "returns only the requested byte range" do
      headers  = HTTP::Headers{"Range" => "bytes=0-9"}
      request  = HTTP::Request.new("GET", "/raw/video.mp4", headers)
      response = call_request_on_app(request)
      response.body.bytesize.should eq(10)
    end

    it "returns 404 for a non-existent file" do
      request  = HTTP::Request.new("GET", "/raw/nonexistent.jpg")
      response = call_request_on_app(request)
      response.status_code.should eq(404)
    end
  end

  # ----- 9.2: path traversal prevention -----
  # Note: Kemal's StaticFileHandler normalises '..' in URL paths via 302 redirect
  # before our route handlers run. For paths that DO reach safe_path (no '..'), our
  # handler returns 400 when safe_path returns nil, or 404 when the resolved path
  # does not exist. The unit tests in file_browser_spec.cr verify safe_path directly.
  # These HTTP-level tests confirm the server never exposes file content for traversal.

  describe "Path traversal prevention" do
    it "does not serve file content for .. traversal in /browse/*path" do
      request  = HTTP::Request.new("GET", "/browse/../../etc/passwd")
      response = call_request_on_app(request)
      # Kemal normalises '..' → 302 redirect; safe_path guards anything reaching the handler
      [302, 400, 404].includes?(response.status_code).should be_true
      response.body.should_not contain("root:")  # must not expose /etc/passwd content
    end

    it "does not serve file content for .. traversal in /api/files/*path" do
      request  = HTTP::Request.new("GET", "/api/files/../../etc/passwd")
      response = call_request_on_app(request)
      [302, 400, 404].includes?(response.status_code).should be_true
      response.body.should_not contain("root:")
    end

    it "does not serve file content for .. traversal in /view/*path" do
      request  = HTTP::Request.new("GET", "/view/../../etc/passwd")
      response = call_request_on_app(request)
      [302, 400, 404].includes?(response.status_code).should be_true
      response.body.should_not contain("root:")
    end

    it "does not serve file content for .. traversal in /raw/*path" do
      request  = HTTP::Request.new("GET", "/raw/../../etc/passwd")
      response = call_request_on_app(request)
      [302, 400, 404].includes?(response.status_code).should be_true
      response.body.should_not contain("root:")
    end

    it "does not serve file content for .. traversal in /thumbnail/*path" do
      request  = HTTP::Request.new("GET", "/thumbnail/../../etc/passwd")
      response = call_request_on_app(request)
      [302, 400, 404].includes?(response.status_code).should be_true
      response.body.should_not contain("root:")
    end

    it "safe_path returns nil for .. traversal (unit-level guard)" do
      # Confirm the guard that protects all HTTP handlers works correctly
      FileBrowser.safe_path(media_root, "../../etc/passwd").should be_nil
      FileBrowser.safe_path(media_root, "../etc/passwd").should be_nil
    end
  end

  # ----- 7.3: thumbnail route -----

  describe "GET /thumbnail/*path" do
    it "returns 200 (JPEG) or 302 (fallback) for an image file" do
      request  = HTTP::Request.new("GET", "/thumbnail/photo.jpg")
      response = call_request_on_app(request)
      [200, 302].includes?(response.status_code).should be_true
    end

    it "returns 404 for a non-existent file" do
      request  = HTTP::Request.new("GET", "/thumbnail/nonexistent.jpg")
      response = call_request_on_app(request)
      response.status_code.should eq(404)
    end

    it "redirects to /no-thumbnail.svg on thumbnail generation failure" do
      # video.mp4 contains plain ASCII — ffmpeg will fail to process it
      request  = HTTP::Request.new("GET", "/thumbnail/video.mp4")
      response = call_request_on_app(request)
      # Either 200 if ffmpeg succeeds, or 302 redirect to fallback
      [200, 302].includes?(response.status_code).should be_true
      if response.status_code == 302
        response.headers["Location"].should eq("/no-thumbnail.svg")
      end
    end
  end
end
