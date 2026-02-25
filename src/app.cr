require "kemal"
require "./config"
require "./services/mime"
require "./services/file_browser"
require "./services/thumbnail"
require "json"
require "ecr"
require "uri"

module AppRouter
  def self.setup(config : AppConfig = CONFIG)
    logging false

    # GET / → redirect to the root browse page
    get "/" do |env|
      env.redirect "/browse/"
    end

    # GET /browse/ → root directory listing (SSR HTML)
    get "/browse/" do |env|
      sort_key     = FileBrowser.parse_sort_key(env.params.query["sort"]? || "")
      sort_dir     = FileBrowser.parse_sort_dir(env.params.query["order"]? || "")
      entries      = FileBrowser.list_entries(config.media_root, "", 0, config.items_per_page, sort_key, sort_dir) || [] of FileEntry
      current_path = ""
      title        = "Media Viewer"
      content      = ECR.render("src/views/directory.ecr")
      ECR.render("src/views/layout.ecr")
    end

    # GET /browse/*path → subdirectory listing (SSR HTML)
    get "/browse/*path" do |env|
      rel_path = URI.decode(env.params.url["path"])
      abs_path = FileBrowser.safe_path(config.media_root, rel_path)
      halt env, status_code: 400, response: "Bad Request" if abs_path.nil?
      halt env, status_code: 404, response: "Not Found" unless Dir.exists?(abs_path)

      sort_key     = FileBrowser.parse_sort_key(env.params.query["sort"]? || "")
      sort_dir     = FileBrowser.parse_sort_dir(env.params.query["order"]? || "")
      entries      = FileBrowser.list_entries(config.media_root, rel_path, 0, config.items_per_page, sort_key, sort_dir) || [] of FileEntry
      current_path = rel_path
      title        = rel_path
      content      = ECR.render("src/views/directory.ecr")
      ECR.render("src/views/layout.ecr")
    end

    # GET /api/files/ → root directory as JSON (infinite scroll)
    get "/api/files/" do |env|
      offset   = env.params.query["offset"]?.try(&.to_i?) || 0
      limit    = [[env.params.query["limit"]?.try(&.to_i?) || 50, 1].max, 100].min
      sort_key = FileBrowser.parse_sort_key(env.params.query["sort"]? || "")
      sort_dir = FileBrowser.parse_sort_dir(env.params.query["order"]? || "")
      entries  = FileBrowser.list_entries(config.media_root, "", offset, limit, sort_key, sort_dir) || [] of FileEntry
      env.response.content_type = "application/json"
      entries.to_json
    end

    # GET /api/files/*path → subdirectory as JSON (infinite scroll)
    get "/api/files/*path" do |env|
      rel_path = URI.decode(env.params.url["path"])
      abs_path = FileBrowser.safe_path(config.media_root, rel_path)
      halt env, status_code: 400, response: "Bad Request" if abs_path.nil?
      halt env, status_code: 404, response: "Not Found" unless Dir.exists?(abs_path)

      offset   = env.params.query["offset"]?.try(&.to_i?) || 0
      limit    = [[env.params.query["limit"]?.try(&.to_i?) || 50, 1].max, 100].min
      sort_key = FileBrowser.parse_sort_key(env.params.query["sort"]? || "")
      sort_dir = FileBrowser.parse_sort_dir(env.params.query["order"]? || "")
      entries  = FileBrowser.list_entries(config.media_root, rel_path, offset, limit, sort_key, sort_dir) || [] of FileEntry
      env.response.content_type = "application/json"
      entries.to_json
    end

    # GET /view/*path → viewer page (SSR HTML) with prev/next navigation
    get "/view/*path" do |env|
      rel_path = URI.decode(env.params.url["path"])
      abs_path = FileBrowser.safe_path(config.media_root, rel_path)
      halt env, status_code: 400, response: "Bad Request" if abs_path.nil?
      halt env, status_code: 404, response: "Not Found" unless File.exists?(abs_path)

      # Gather sibling file entries for prev/next navigation
      parent     = File.dirname(rel_path)
      parent     = "" if parent == "."
      all_entries   = FileBrowser.list_entries(config.media_root, parent, 0, 10_000) || [] of FileEntry
      file_entries  = all_entries.reject(&.is_dir)
      current_idx   = file_entries.index { |e| e.path == rel_path }
      halt env, status_code: 404, response: "Not Found" unless current_idx

      entry      = file_entries[current_idx]
      prev_entry = current_idx > 0 ? file_entries[current_idx - 1].as(FileEntry?) : nil.as(FileEntry?)
      next_entry = current_idx < file_entries.size - 1 ? file_entries[current_idx + 1].as(FileEntry?) : nil.as(FileEntry?)

      title   = entry.name
      content = ECR.render("src/views/viewer.ecr")
      ECR.render("src/views/layout.ecr")
    end

    # GET /raw/*path → serve file with correct Content-Type; supports Range requests
    get "/raw/*path" do |env|
      rel_path = URI.decode(env.params.url["path"])
      abs_path = FileBrowser.safe_path(config.media_root, rel_path)
      halt env, status_code: 400, response: "Bad Request" if abs_path.nil?
      halt env, status_code: 404, response: "Not Found" unless File.exists?(abs_path)

      mime = MimeService.content_type(File.basename(rel_path))
      send_file(env, abs_path, mime)
    end

    # GET /thumbnail/*path → JPEG thumbnail; 302 to /no-thumbnail.svg on failure
    get "/thumbnail/*path" do |env|
      rel_path = URI.decode(env.params.url["path"])
      abs_path = FileBrowser.safe_path(config.media_root, rel_path)
      halt env, status_code: 400, response: "Bad Request" if abs_path.nil?
      halt env, status_code: 404, response: "Not Found" unless File.exists?(abs_path)

      file_info  = File.info(abs_path)
      media_type = MimeService.media_type(File.basename(rel_path))
      thumb_path = ThumbnailService.fetch_or_generate(
        abs_path,
        file_info.modification_time,
        media_type,
        config.cache_dir,
        config.thumbnail_size
      )

      if thumb_path
        send_file(env, thumb_path, "image/jpeg")
      else
        env.redirect "/no-thumbnail.svg"
      end
    end
  end
end

# Start the server only when NOT in test mode
unless ENV["MEDIA_VIEWER_TEST"]?
  AppRouter.setup(CONFIG)
  Kemal.config.port = CONFIG.port
  Kemal.run
end
