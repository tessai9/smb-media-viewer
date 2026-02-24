require "digest/sha256"
require "file_utils"
require "./mime"

module ThumbnailService
  # Returns the path to a cached JPEG thumbnail, generating it if needed.
  # Returns nil on any generation failure — never raises.
  def self.fetch_or_generate(
    abs_path   : String,
    mtime      : Time,
    media_type : MediaType,
    cache_dir  : String,
    size       : Int32
  ) : String?
    FileUtils.mkdir_p(cache_dir)

    cache_key  = Digest::SHA256.hexdigest("#{abs_path}:#{mtime.to_unix}")
    cache_path = File.join(cache_dir, "#{cache_key}.jpg")

    # Cache hit — return immediately without regenerating.
    return cache_path if File.exists?(cache_path)

    success = generate(media_type, abs_path, cache_path, size)
    (success && File.exists?(cache_path)) ? cache_path : nil
  rescue ex
    STDERR.puts "ThumbnailService error for #{abs_path}: #{ex.message}"
    nil
  end

  # Dispatches to the correct generator based on media type.
  private def self.generate(
    media_type : MediaType,
    src        : String,
    dest       : String,
    size       : Int32
  ) : Bool
    case media_type
    when MediaType::Image then generate_image(src, dest, size)
    when MediaType::Video then generate_video(src, dest, size)
    when MediaType::Pdf   then generate_pdf(src, dest, size)
    else                       false
    end
  end

  # Runs an external command without shell expansion.
  # Returns false (never raises) if the command is not found or exits non-zero.
  private def self.run_command(cmd : String, args : Array(String)) : Bool
    err_io = IO::Memory.new
    status = Process.run(
      cmd,
      args: args,
      output: Process::Redirect::Close,
      error: err_io
    )
    unless status.success?
      err = err_io.to_s.strip
      STDERR.puts "ThumbnailService: #{cmd} exited #{status.exit_code}#{err.empty? ? "" : " — #{err}"}"
    end
    status.success?
  rescue ex
    STDERR.puts "ThumbnailService: #{cmd} not found or failed: #{ex.message}"
    false
  end

  # Image: vipsthumbnail <src> --size NxN -o <dest>[Q=80]
  private def self.generate_image(src : String, dest : String, size : Int32) : Bool
    run_command("vipsthumbnail", [src, "--size", "#{size}x#{size}", "-o", "#{dest}[Q=80]"])
  end

  # Video: ffmpeg extracts frame at 1s → vipsthumbnail resizes → temp file deleted.
  private def self.generate_video(src : String, dest : String, size : Int32) : Bool
    tmp = "#{dest}.tmp_frame.jpg"
    ok  = run_command("ffmpeg", ["-ss", "1", "-i", src, "-frames:v", "1", "-y", tmp])
    return false unless ok && File.exists?(tmp)

    result = generate_image(tmp, dest, size)
    File.delete(tmp) rescue nil
    result
  end

  # PDF: pdftoppm renders page 1 → vipsthumbnail resizes → temp files deleted.
  private def self.generate_pdf(src : String, dest : String, size : Int32) : Bool
    tmp_prefix = "#{dest}.tmp_pdf"
    ok = run_command("pdftoppm", ["-jpeg", "-f", "1", "-l", "1", src, tmp_prefix])
    return false unless ok

    tmp_files = Dir.glob("#{tmp_prefix}-*.jpg")
    return false if tmp_files.empty?

    result = generate_image(tmp_files.first, dest, size)
    tmp_files.each { |f| File.delete(f) rescue nil }
    result
  end
end
