require "./spec_helper"

describe "REST API v1" do
  test_config = uninitialized AppConfig
  media_root  = uninitialized String
  cache_dir   = uninitialized String

  before_each do
    media_root = "/tmp/test-apiv1-#{Random.new.hex(6)}"
    cache_dir  = "/tmp/test-apiv1-cache-#{Random.new.hex(6)}"

    FileUtils.mkdir_p(File.join(media_root, "subdir"))
    FileUtils.mkdir_p(cache_dir)

    File.open(File.join(media_root, "photo.jpg"), "wb") { |f| f.write(JPEG_BYTES) }
    File.write(File.join(media_root, "video.mp4"), "A" * 100)
    File.write(File.join(media_root, "notes.txt"), "not media")  # unsupported → excluded from listings
    File.open(File.join(media_root, "subdir", "inner.jpg"), "wb") { |f| f.write(JPEG_BYTES) }

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

  describe "GET /api/v1/list/" do
    it "returns a wrapper object with path, pagination fields and entries" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/list/"))
      response.status_code.should eq(200)
      response.headers["Content-Type"].should contain("application/json")

      json = JSON.parse(response.body)
      json["path"].as_s.should eq("")
      json["offset"].as_i.should eq(0)
      json["total"].as_i.should eq(3)  # subdir, photo.jpg, video.mp4 (notes.txt excluded)
      json["entries"].as_a.map(&.["name"].as_s).should contain("photo.jpg")
    end

    it "excludes unsupported files from entries" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/list/"))
      names = JSON.parse(response.body)["entries"].as_a.map(&.["name"].as_s)
      names.should_not contain("notes.txt")
    end

    it "paginates with offset/limit while reporting the full total" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/list/?offset=1&limit=1"))
      json = JSON.parse(response.body)
      json["entries"].as_a.size.should eq(1)
      json["offset"].as_i.should eq(1)
      json["limit"].as_i.should eq(1)
      json["total"].as_i.should eq(3)
    end

    it "lists directories before files" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/list/"))
      entries = JSON.parse(response.body)["entries"].as_a
      entries.first["name"].as_s.should eq("subdir")
      entries.first["is_dir"].as_bool.should be_true
    end
  end

  describe "GET /api/v1/list/*path" do
    it "lists a subdirectory" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/list/subdir"))
      response.status_code.should eq(200)
      json = JSON.parse(response.body)
      json["path"].as_s.should eq("subdir")
      json["entries"].as_a.map(&.["name"].as_s).should contain("inner.jpg")
    end

    it "returns 404 JSON for a non-existent directory" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/list/nonexistent"))
      response.status_code.should eq(404)
      JSON.parse(response.body)["error"].as_s.should_not be_empty
    end

    it "does not expose content outside media_root for .. traversal" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/list/../../etc"))
      [302, 400, 404].includes?(response.status_code).should be_true
      response.body.should_not contain("passwd")
    end
  end

  describe "GET /api/v1/info/*path" do
    it "returns detailed info for a file" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/info/photo.jpg"))
      response.status_code.should eq(200)
      json = JSON.parse(response.body)
      json["name"].as_s.should eq("photo.jpg")
      json["path"].as_s.should eq("photo.jpg")
      json["is_dir"].as_bool.should be_false
      json["size"].as_i64.should eq(JPEG_BYTES.size.to_i64)
      json["media_type"].as_s.should eq("image")
      json["content_type"].as_s.should eq("image/jpeg")
      json["extension"].as_s.should eq("jpg")
      json["mtime_unix"].as_i64.should be > 0
    end

    it "returns directory info with media_type=directory" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/info/subdir"))
      json = JSON.parse(response.body)
      json["is_dir"].as_bool.should be_true
      json["media_type"].as_s.should eq("directory")
      json["size"].as_i64.should eq(0)
      json["content_type"]?.should be_nil  # omitted for directories
    end

    it "returns info for the media root via /api/v1/info/" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/info/"))
      response.status_code.should eq(200)
      json = JSON.parse(response.body)
      json["name"].as_s.should eq("/")
      json["is_dir"].as_bool.should be_true
    end

    it "returns 404 JSON for a non-existent path" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/info/nope.jpg"))
      response.status_code.should eq(404)
      JSON.parse(response.body)["error"].as_s.should_not be_empty
    end
  end

  describe "GET /api/v1/content/*path" do
    it "serves the file body with the correct Content-Type" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/content/photo.jpg"))
      response.status_code.should eq(200)
      response.headers["Content-Type"].should contain("image/jpeg")
      response.body.bytesize.should eq(JPEG_BYTES.size)
    end

    it "supports Range requests with 206" do
      headers  = HTTP::Headers{"Range" => "bytes=0-9"}
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/content/video.mp4", headers))
      response.status_code.should eq(206)
      response.headers["Content-Range"].should contain("bytes 0-9/100")
      response.body.bytesize.should eq(10)
    end

    it "returns 404 JSON for a non-existent file" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/content/nope.jpg"))
      response.status_code.should eq(404)
    end

    it "returns 404 for a directory path" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/content/subdir"))
      response.status_code.should eq(404)
    end

    it "does not expose file content for .. traversal" do
      response = call_request_on_app(HTTP::Request.new("GET", "/api/v1/content/../../etc/passwd"))
      [302, 400, 404].includes?(response.status_code).should be_true
      response.body.should_not contain("root:")
    end
  end
end
