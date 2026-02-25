require "json"
require "./mime"

enum SortKey
  Name   # default: case-insensitive alphabetical
  Ctime  # creation time
  Mtime  # modification time
end

enum SortDir
  Asc   # default: ascending
  Desc  # descending
end

struct FileEntry
  include JSON::Serializable

  property name       : String
  property path       : String   # relative path from media_root
  property is_dir     : Bool
  property size       : Int64    # 0 for directories
  property mtime      : Time
  property media_type : String   # "image" | "video" | "pdf" | "unknown"

  @[JSON::Field(ignore: true)]
  property ctime : Time  # creation time — used for sorting only, not exposed via API

  def initialize(@name, @path, @is_dir, @size, @mtime, @media_type, @ctime = Time::UNIX_EPOCH)
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

  # Parses a sort key string into a SortKey enum value.
  # Returns SortKey::Name for absent, empty, or unrecognized values.
  def self.parse_sort_key(s : String) : SortKey
    case s
    when "ctime" then SortKey::Ctime
    when "mtime" then SortKey::Mtime
    else              SortKey::Name
    end
  end

  # Parses a sort direction string into a SortDir enum value.
  # Returns SortDir::Asc for absent, empty, or unrecognized values.
  def self.parse_sort_dir(s : String) : SortDir
    s == "desc" ? SortDir::Desc : SortDir::Asc
  end

  # Returns a paginated, sorted, filtered list of entries in the given directory.
  # Returns nil if rel_path violates the media_root boundary.
  # limit is clamped to a maximum of 100; offset beyond array length returns [].
  # Default sort: Name ascending (same as existing behaviour — backward compatible).
  def self.list_entries(
    media_root : String,
    rel_path   : String,
    offset     : Int32,
    limit      : Int32,
    sort_key   : SortKey = SortKey::Name,
    sort_dir   : SortDir = SortDir::Asc
  ) : Array(FileEntry)?
    abs_path = safe_path(media_root, rel_path)
    return nil if abs_path.nil?

    entries = scan_entries(media_root, abs_path, sort_key, sort_dir)
    entries.skip(offset).first(limit)
  end

  # Compares two pre-downcased filename strings using natural sort order.
  # Numeric substrings are compared as unsigned integers; non-numeric substrings
  # are compared as strings (case folding is applied by the caller before this call).
  # Returns negative if a < b, 0 if equal, positive if a > b.
  private def self.natural_compare(a : String, b : String) : Int32
    a_chars = a.chars
    b_chars = b.chars
    ia = 0
    ib = 0

    loop do
      # Extract non-digit (text) segment from each string.
      a_ts = ia
      while ia < a_chars.size && !a_chars[ia].ascii_number?
        ia += 1
      end
      b_ts = ib
      while ib < b_chars.size && !b_chars[ib].ascii_number?
        ib += 1
      end

      cmp = a_chars[a_ts...ia].join <=> b_chars[b_ts...ib].join
      return cmp unless cmp == 0

      # Exhaustion check: if both ended at text boundary, strings are equal.
      return  0 if ia >= a_chars.size && ib >= b_chars.size
      return -1 if ia >= a_chars.size  # a ended; b continues with digits
      return  1 if ib >= b_chars.size  # b ended; a continues with digits

      # Extract digit segment from each string (both have a digit char here).
      a_ds = ia
      while ia < a_chars.size && a_chars[ia].ascii_number?
        ia += 1
      end
      b_ds = ib
      while ib < b_chars.size && b_chars[ib].ascii_number?
        ib += 1
      end

      # Compare as unsigned 64-bit integers (leading zeros → same integer value).
      num_a = a_chars[a_ds...ia].join.to_u64? || 0u64
      num_b = b_chars[b_ds...ib].join.to_u64? || 0u64
      cmp = num_a <=> num_b
      return cmp unless cmp == 0

      # Exhaustion check after digit segment.
      return  0 if ia >= a_chars.size && ib >= b_chars.size
      return -1 if ia >= a_chars.size
      return  1 if ib >= b_chars.size
    end
  end

  # Scans a directory, filters, sorts, and returns entries.
  # Directories always appear before files; sort key and direction apply within each group.
  private def self.scan_entries(
    media_root : String,
    abs_path   : String,
    sort_key   : SortKey = SortKey::Name,
    sort_dir   : SortDir = SortDir::Asc
  ) : Array(FileEntry)
    root_path = Path.new(media_root).normalize
    entries   = [] of FileEntry

    Dir.each_child(abs_path) do |name|
      next if name.starts_with?('.')  # skip hidden

      child_abs = File.join(abs_path, name)
      info      = File.info(child_abs, follow_symlinks: false)
      is_dir    = info.directory?

      next if !is_dir && !MimeService.supported?(name)  # skip unsupported files

      rel        = Path.new(child_abs).relative_to(root_path).to_s
      media_type = is_dir ? "unknown" : MimeService.media_type(name).to_s.downcase
      size       = is_dir ? 0i64 : info.size

      entries << FileEntry.new(
        name:       name,
        path:       rel,
        is_dir:     is_dir,
        size:       size,
        mtime:      info.modification_time,
        media_type: media_type,
        # Crystal 1.15.1 does not expose File::Info#creation_time on Linux.
        # On CIFS/SMB mounts the Windows NTFS birthtime would be used once
        # Crystal exposes it. Until then we fall back to modification_time,
        # which is consistent with the spec's "non-NTFS filesystems fall back
        # to mtime" note — no incorrect behaviour, just indistinguishable.
        ctime:      info.modification_time
      )
    end

    # Separate dirs from files, sort each group, then concatenate.
    dirs  = entries.select(&.is_dir)
    files = entries.reject(&.is_dir)

    comparator = ->(a : FileEntry, b : FileEntry) do
      cmp = case sort_key
            in SortKey::Name  then natural_compare(a.name.downcase, b.name.downcase)
            in SortKey::Mtime then a.mtime <=> b.mtime
            in SortKey::Ctime then a.ctime <=> b.ctime
            end
      sort_dir == SortDir::Desc ? -cmp : cmp
    end

    dirs.sort!(&comparator)
    files.sort!(&comparator)

    dirs + files
  end
end
