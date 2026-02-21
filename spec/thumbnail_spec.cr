require "spec"
require "file_utils"
require "digest/sha256"
require "../src/services/mime"
require "../src/services/thumbnail"

private def with_tmpdir(&block : String ->)
  tmpdir = File.join(Dir.tempdir, "thumb_test_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(tmpdir)
  begin
    block.call(tmpdir)
  ensure
    FileUtils.rm_rf(tmpdir)
  end
end

# Minimal 1×1 white pixel PPM (binary P6 — vipsthumbnail can read this)
private def write_test_ppm(path : String)
  File.open(path, "wb") do |f|
    f.print("P6\n1 1\n255\n")
    f.write(Bytes[255, 255, 255])
  end
end

describe ThumbnailService do
  describe ".fetch_or_generate — cache key & disk cache (task 5.1)" do
    it "creates cache directory if it does not exist" do
      with_tmpdir do |tmpdir|
        cache_dir = File.join(tmpdir, "cache", "nested")
        src = File.join(tmpdir, "img.ppm")
        write_test_ppm(src)
        mtime = File.info(src).modification_time

        ThumbnailService.fetch_or_generate(src, mtime, MediaType::Image, cache_dir, 50)
        Dir.exists?(cache_dir).should be_true
      end
    end

    it "generates the same cache key for identical abs_path and mtime" do
      with_tmpdir do |tmpdir|
        src   = "/some/absolute/path/photo.jpg"
        mtime = Time.utc(2024, 6, 1, 12, 0, 0)

        # Derive expected key the same way the implementation does
        expected_key  = Digest::SHA256.hexdigest("#{src}:#{mtime.to_unix}")
        expected_name = "#{expected_key}.jpg"

        cache_dir = File.join(tmpdir, "cache")
        FileUtils.mkdir_p(cache_dir)
        File.write(File.join(cache_dir, expected_name), "cached")

        result = ThumbnailService.fetch_or_generate(src, mtime, MediaType::Image, cache_dir, 50)
        result.should_not be_nil
        File.basename(result.not_nil!).should eq(expected_name)
      end
    end

    it "produces different cache keys for different mtimes (auto-invalidation)" do
      with_tmpdir do |tmpdir|
        cache_dir = File.join(tmpdir, "cache")
        src       = File.join(tmpdir, "img.ppm")
        write_test_ppm(src)

        mtime1 = Time.utc(2024, 1, 1)
        mtime2 = Time.utc(2024, 1, 2)

        path1 = ThumbnailService.fetch_or_generate(src, mtime1, MediaType::Image, cache_dir, 50)
        path2 = ThumbnailService.fetch_or_generate(src, mtime2, MediaType::Image, cache_dir, 50)

        path1.should_not be_nil
        path2.should_not be_nil
        path1.should_not eq(path2)
      end
    end

    it "returns the pre-existing cached file without regenerating (cache hit)" do
      with_tmpdir do |tmpdir|
        cache_dir = File.join(tmpdir, "cache")
        FileUtils.mkdir_p(cache_dir)

        src   = "/nonexistent/source.jpg"   # source does NOT exist
        mtime = Time.utc(2025, 3, 15)

        cache_key  = Digest::SHA256.hexdigest("#{src}:#{mtime.to_unix}")
        cache_path = File.join(cache_dir, "#{cache_key}.jpg")
        File.write(cache_path, "pre-cached data")

        result = ThumbnailService.fetch_or_generate(src, mtime, MediaType::Image, cache_dir, 50)
        result.should eq(cache_path)
      end
    end

    it "returns nil when source does not exist and no cache (graceful failure)" do
      with_tmpdir do |tmpdir|
        cache_dir = File.join(tmpdir, "cache")
        result = ThumbnailService.fetch_or_generate(
          "/nonexistent/photo.jpg",
          Time.utc,
          MediaType::Image,
          cache_dir,
          50
        )
        result.should be_nil
      end
    end
  end

  describe ".fetch_or_generate — thumbnail generation (task 5.2)" do
    it "returns nil for MediaType::Unknown without crashing" do
      with_tmpdir do |tmpdir|
        cache_dir = File.join(tmpdir, "cache")
        src       = File.join(tmpdir, "img.ppm")
        write_test_ppm(src)
        mtime = File.info(src).modification_time

        result = ThumbnailService.fetch_or_generate(src, mtime, MediaType::Unknown, cache_dir, 50)
        result.should be_nil
      end
    end

    it "generates a JPEG thumbnail for an image file (vipsthumbnail)" do
      with_tmpdir do |tmpdir|
        cache_dir = File.join(tmpdir, "cache")
        src       = File.join(tmpdir, "img.ppm")
        write_test_ppm(src)
        mtime = File.info(src).modification_time

        result = ThumbnailService.fetch_or_generate(src, mtime, MediaType::Image, cache_dir, 50)
        result.should_not be_nil
        File.exists?(result.not_nil!).should be_true
        result.not_nil!.should end_with(".jpg")
      end
    end

    it "returns the cached thumbnail on second call (no duplicate generation)" do
      with_tmpdir do |tmpdir|
        cache_dir = File.join(tmpdir, "cache")
        src       = File.join(tmpdir, "img.ppm")
        write_test_ppm(src)
        mtime = File.info(src).modification_time

        first  = ThumbnailService.fetch_or_generate(src, mtime, MediaType::Image, cache_dir, 50)
        second = ThumbnailService.fetch_or_generate(src, mtime, MediaType::Image, cache_dir, 50)

        first.should eq(second)
      end
    end

    it "creates a new cache file when mtime changes (auto-invalidation integration)" do
      with_tmpdir do |tmpdir|
        cache_dir = File.join(tmpdir, "cache")
        src       = File.join(tmpdir, "img.ppm")
        write_test_ppm(src)

        mtime1 = File.info(src).modification_time
        # Simulate a later mtime (1 second ahead — no actual filesystem sleep needed)
        mtime2 = mtime1 + 1.second

        result1 = ThumbnailService.fetch_or_generate(src, mtime1, MediaType::Image, cache_dir, 50)
        result2 = ThumbnailService.fetch_or_generate(src, mtime2, MediaType::Image, cache_dir, 50)

        result1.should_not be_nil
        result2.should_not be_nil
        # Different mtimes produce different cache paths → new file generated
        result1.should_not eq(result2)
        File.exists?(result2.not_nil!).should be_true
      end
    end

    it "generates a thumbnail for a video file (ffmpeg → vipsthumbnail)" do
      with_tmpdir do |tmpdir|
        cache_dir = File.join(tmpdir, "cache")
        src       = File.join(tmpdir, "clip.mp4")

        # Create a 3-second blue test video with ffmpeg
        created = Process.run(
          "ffmpeg",
          args: ["-f", "lavfi", "-i", "color=c=blue:s=16x16:d=3", "-y", src],
          output: Process::Redirect::Close,
          error: Process::Redirect::Close
        ).success?

        if created
          mtime  = File.info(src).modification_time
          result = ThumbnailService.fetch_or_generate(src, mtime, MediaType::Video, cache_dir, 50)
          result.should_not be_nil
          File.exists?(result.not_nil!).should be_true
        else
          pending "ffmpeg not available — skipping video thumbnail test"
        end
      end
    end

    it "leaves no temporary files after video thumbnail generation" do
      with_tmpdir do |tmpdir|
        cache_dir = File.join(tmpdir, "cache")
        src       = File.join(tmpdir, "clip.mp4")

        created = Process.run(
          "ffmpeg",
          args: ["-f", "lavfi", "-i", "color=c=red:s=16x16:d=3", "-y", src],
          output: Process::Redirect::Close,
          error: Process::Redirect::Close
        ).success?

        if created
          mtime = File.info(src).modification_time
          ThumbnailService.fetch_or_generate(src, mtime, MediaType::Video, cache_dir, 50)
          # Only the final .jpg should remain in cache_dir — no .tmp_* files
          leftovers = Dir.glob(File.join(cache_dir, "*.tmp_*"))
          leftovers.should be_empty
        else
          pending "ffmpeg not available"
        end
      end
    end
  end
end
