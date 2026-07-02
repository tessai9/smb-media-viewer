require "json"
require "./mime"
require "./image_metadata"

# Detailed information about a single file or directory.
# Exposed via GET /api/v1/info/*path and the MCP get_file_info tool.
#
# Nil fields (content_type / extension / ai_metadata) are omitted from the
# JSON output — JSON::Serializable does not emit null fields by default.
struct FileDetails
  include JSON::Serializable

  property name         : String
  property path         : String   # relative path from media_root ("" = root)
  property is_dir       : Bool
  property size         : Int64    # 0 for directories
  property mtime        : Time
  property mtime_unix   : Int64
  property media_type   : String   # "image" | "video" | "pdf" | "directory" | "unknown"
  property content_type : String?  # nil for directories
  property extension    : String?  # nil for directories and extension-less files
  property ai_metadata  : ImageMetadataService::AiImageMetadata?  # PNG AI generation metadata

  def initialize(@name, @path, @is_dir, @size, @mtime, @mtime_unix,
                 @media_type, @content_type, @extension, @ai_metadata)
  end

  # Builds details for an absolute path that has ALREADY been validated with
  # FileBrowser.safe_path. rel_path is the media_root-relative path.
  def self.build(abs_path : String, rel_path : String) : FileDetails
    info  = File.info(abs_path)
    mtime = info.modification_time
    name  = rel_path.empty? ? "/" : File.basename(rel_path)

    if info.directory?
      new(name, rel_path, true, 0i64, mtime, mtime.to_unix,
          "directory", nil, nil, nil)
    else
      media_type = MimeService.media_type(name).to_s.downcase
      ext        = File.extname(name).lstrip('.').downcase
      ai_meta    = media_type == "image" ? ImageMetadataService.extract(abs_path) : nil
      new(name, rel_path, false, info.size, mtime, mtime.to_unix,
          media_type, MimeService.content_type(name), ext.empty? ? nil : ext, ai_meta)
    end
  end
end
