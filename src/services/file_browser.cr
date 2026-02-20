require "./mime"

struct FileEntry
  property name       : String
  property path       : String   # relative path from media_root
  property is_dir     : Bool
  property size       : Int64    # 0 for directories
  property mtime      : Time
  property media_type : String   # "image" | "video" | "pdf" | "unknown"

  def initialize(@name, @path, @is_dir, @size, @mtime, @media_type)
  end
end

module FileBrowser
  # Returns the absolute path if rel_path resolves within media_root, nil otherwise.
  #
  # Invariant: callers MUST return HTTP 400 or 404 when this returns nil.
  # This prevents path traversal attacks — never access the filesystem without
  # first calling safe_path and checking for nil.
  def self.safe_path(media_root : String, rel_path : String) : String?
    root = Path.new(media_root).normalize

    # Reject absolute paths — callers must supply relative paths only.
    return nil if rel_path.starts_with?('/')

    # Join to root and normalize (resolves .., ., redundant separators).
    candidate = root.join(rel_path).normalize

    root_str      = root.to_s
    candidate_str = candidate.to_s

    # Accept only paths that equal root or are direct descendants.
    if candidate_str == root_str || candidate_str.starts_with?(root_str + File::SEPARATOR)
      candidate_str
    else
      nil
    end
  end

  # Returns a paginated, sorted, filtered list of entries in the given directory.
  # Returns nil if rel_path violates the media_root boundary.
  # limit is clamped to a maximum of 100; offset beyond array length returns [].
  def self.list_entries(
    media_root : String,
    rel_path   : String,
    offset     : Int32,
    limit      : Int32
  ) : Array(FileEntry)?
    abs_path = safe_path(media_root, rel_path)
    return nil if abs_path.nil?

    clamped_limit = [limit, 100].min
    entries       = scan_entries(media_root, abs_path)
    entries.skip(offset).first(clamped_limit)
  end

  # Scans a directory, filters, and returns entries sorted by:
  # directories first (alpha), then files (alpha), both case-insensitive.
  private def self.scan_entries(media_root : String, abs_path : String) : Array(FileEntry)
    root_path = Path.new(media_root).normalize
    entries   = [] of FileEntry

    Dir.each_child(abs_path) do |name|
      next if name.starts_with?('.')  # skip hidden

      child_abs = File.join(abs_path, name)
      info      = File.info(child_abs, follow_symlinks: false)
      is_dir    = info.directory?

      next if !is_dir && !MimeService.supported?(name)  # skip unsupported files

      rel = Path.new(child_abs).relative_to(root_path).to_s
      media_type = is_dir ? "unknown" : MimeService.media_type(name).to_s.downcase
      size       = is_dir ? 0i64 : info.size

      entries << FileEntry.new(
        name:       name,
        path:       rel,
        is_dir:     is_dir,
        size:       size,
        mtime:      info.modification_time,
        media_type: media_type
      )
    end

    entries.sort! do |a, b|
      if a.is_dir == b.is_dir
        a.name.downcase <=> b.name.downcase
      else
        a.is_dir ? -1 : 1
      end
    end

    entries
  end
end
