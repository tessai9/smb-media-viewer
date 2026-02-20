enum MediaType
  Image   # jpg, jpeg, png, gif, webp, bmp, svg
  Video   # mp4, webm, mkv, avi, mov
  Pdf     # pdf
  Unknown
end

module MimeService
  MEDIA_TYPE_MAP = {
    "jpg"  => MediaType::Image,
    "jpeg" => MediaType::Image,
    "png"  => MediaType::Image,
    "gif"  => MediaType::Image,
    "webp" => MediaType::Image,
    "bmp"  => MediaType::Image,
    "svg"  => MediaType::Image,
    "mp4"  => MediaType::Video,
    "webm" => MediaType::Video,
    "mkv"  => MediaType::Video,
    "avi"  => MediaType::Video,
    "mov"  => MediaType::Video,
    "pdf"  => MediaType::Pdf,
  }

  CONTENT_TYPE_MAP = {
    "jpg"  => "image/jpeg",
    "jpeg" => "image/jpeg",
    "png"  => "image/png",
    "gif"  => "image/gif",
    "webp" => "image/webp",
    "bmp"  => "image/bmp",
    "svg"  => "image/svg+xml",
    "mp4"  => "video/mp4",
    "webm" => "video/webm",
    "mkv"  => "video/x-matroska",
    "avi"  => "video/x-msvideo",
    "mov"  => "video/quicktime",
    "pdf"  => "application/pdf",
  }

  # Returns the MediaType for the given filename based on its extension.
  # Extension matching is case-insensitive.
  def self.media_type(filename : String) : MediaType
    ext = File.extname(filename).lstrip('.').downcase
    return MediaType::Unknown if ext.empty?
    MEDIA_TYPE_MAP.fetch(ext, MediaType::Unknown)
  end

  # Returns the MIME Content-Type string for the given filename.
  # Falls back to application/octet-stream for unsupported types.
  def self.content_type(filename : String) : String
    ext = File.extname(filename).lstrip('.').downcase
    CONTENT_TYPE_MAP.fetch(ext, "application/octet-stream")
  end

  # Returns true if the file should be shown in directory listings.
  # Hidden files (dot-prefixed names) and unsupported extensions return false.
  def self.supported?(filename : String) : Bool
    name = File.basename(filename)
    return false if name.starts_with?('.')
    media_type(filename) != MediaType::Unknown
  end
end
