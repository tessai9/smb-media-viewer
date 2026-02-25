require "spec"
require "file_utils"
require "../src/services/file_browser"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Temp dir with image1.jpg, image2.jpg, image10.jpg.
# Lexicographic sort gives [image1, image10, image2]; natural sort must give
# [image1, image2, image10].
private def with_numeric_sort_dir(&block : String ->)
  tmpdir = File.join(Dir.tempdir, "mv_natural_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(tmpdir)
  ["image1.jpg", "image2.jpg", "image10.jpg"].each do |f|
    File.write(File.join(tmpdir, f), "x")
  end
  begin
    block.call(tmpdir)
  ensure
    FileUtils.rm_rf(tmpdir)
  end
end

# Temp dir with multi-segment numeric filenames (mp4 to vary extension).
# Expected ascending order: ep1part2.mp4 → ep1part10.mp4 → ep2part1.mp4
private def with_multiseg_dir(&block : String ->)
  tmpdir = File.join(Dir.tempdir, "mv_multiseg_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(tmpdir)
  ["ep1part2.mp4", "ep1part10.mp4", "ep2part1.mp4"].each do |f|
    File.write(File.join(tmpdir, f), "x")
  end
  begin
    block.call(tmpdir)
  ensure
    FileUtils.rm_rf(tmpdir)
  end
end

# Temp dir with pure alphabetical filenames (no digits).
private def with_alpha_dir(&block : String ->)
  tmpdir = File.join(Dir.tempdir, "mv_alpha_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(tmpdir)
  ["gamma.jpg", "alpha.jpg", "beta.jpg"].each do |f|
    File.write(File.join(tmpdir, f), "x")
  end
  begin
    block.call(tmpdir)
  ensure
    FileUtils.rm_rf(tmpdir)
  end
end

# Temp dir for leading-zero test: file01.jpg, file1.jpg, file10.jpg.
# file01 and file1 both parse to integer 1; file10 must come last.
private def with_leading_zero_dir(&block : String ->)
  tmpdir = File.join(Dir.tempdir, "mv_lz_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(tmpdir)
  ["file01.jpg", "file1.jpg", "file10.jpg"].each do |f|
    File.write(File.join(tmpdir, f), "x")
  end
  begin
    block.call(tmpdir)
  ensure
    FileUtils.rm_rf(tmpdir)
  end
end

# Temp dir for special-character test: _note.jpg vs anote.jpg.
private def with_underscore_dir(&block : String ->)
  tmpdir = File.join(Dir.tempdir, "mv_us_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(tmpdir)
  ["anote.jpg", "_note.jpg"].each do |f|
    File.write(File.join(tmpdir, f), "x")
  end
  begin
    block.call(tmpdir)
  ensure
    FileUtils.rm_rf(tmpdir)
  end
end

# Temp dir for multibyte prefix test: 画像1.jpg, 画像2.jpg, 画像10.jpg.
private def with_japanese_dir(&block : String ->)
  tmpdir = File.join(Dir.tempdir, "mv_ja_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(tmpdir)
  ["画像1.jpg", "画像2.jpg", "画像10.jpg"].each do |f|
    File.write(File.join(tmpdir, f), "x")
  end
  begin
    block.call(tmpdir)
  ensure
    FileUtils.rm_rf(tmpdir)
  end
end

# ---------------------------------------------------------------------------
# Task 2.1 — Core numeric ordering and multi-segment filenames
# ---------------------------------------------------------------------------

describe "FileBrowser.list_entries — natural sort: single numeric segment" do
  it "sorts files with a numeric suffix in numeric order (ascending)" do
    with_numeric_sort_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Asc)
      entries.not_nil!.map(&.name).should eq(["image1.jpg", "image2.jpg", "image10.jpg"])
    end
  end

  it "sorts files with a numeric suffix in numeric order (descending)" do
    with_numeric_sort_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Desc)
      entries.not_nil!.map(&.name).should eq(["image10.jpg", "image2.jpg", "image1.jpg"])
    end
  end
end

describe "FileBrowser.list_entries — natural sort: multi-segment numeric filenames" do
  it "evaluates each numeric segment independently in ascending order" do
    with_multiseg_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Asc)
      entries.not_nil!.map(&.name).should eq(["ep1part2.mp4", "ep1part10.mp4", "ep2part1.mp4"])
    end
  end

  it "evaluates each numeric segment independently in descending order" do
    with_multiseg_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Desc)
      entries.not_nil!.map(&.name).should eq(["ep2part1.mp4", "ep1part10.mp4", "ep1part2.mp4"])
    end
  end
end

describe "FileBrowser.list_entries — natural sort: pure alphabetical names" do
  it "sorts non-numeric filenames in case-insensitive alphabetical order (ascending)" do
    with_alpha_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Asc)
      entries.not_nil!.map(&.name).should eq(["alpha.jpg", "beta.jpg", "gamma.jpg"])
    end
  end

  it "sorts non-numeric filenames in reverse alphabetical order (descending)" do
    with_alpha_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Desc)
      entries.not_nil!.map(&.name).should eq(["gamma.jpg", "beta.jpg", "alpha.jpg"])
    end
  end
end

# ---------------------------------------------------------------------------
# Task 2.2 — Edge cases: leading zeros, special characters, multibyte names
# ---------------------------------------------------------------------------

describe "FileBrowser.list_entries — natural sort: leading zeros" do
  it "treats leading zeros as the same integer value (file01 == file1 < file10)" do
    with_leading_zero_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Asc)
      names = entries.not_nil!.map(&.name)
      # file01 and file1 both parse to integer 1; file10 must appear last.
      names.last.should eq("file10.jpg")
      names.should contain("file01.jpg")
      names.should contain("file1.jpg")
    end
  end
end

describe "FileBrowser.list_entries — natural sort: special ASCII characters" do
  it "sorts underscore before lowercase letters (ASCII 95 < 97)" do
    with_underscore_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Asc)
      entries.not_nil!.map(&.name).should eq(["_note.jpg", "anote.jpg"])
    end
  end
end

describe "FileBrowser.list_entries — natural sort: multibyte filename prefix" do
  it "sorts Japanese-prefixed files by their numeric suffix (ascending)" do
    with_japanese_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Asc)
      entries.not_nil!.map(&.name).should eq(["画像1.jpg", "画像2.jpg", "画像10.jpg"])
    end
  end

  it "sorts Japanese-prefixed files by their numeric suffix (descending)" do
    with_japanese_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Desc)
      entries.not_nil!.map(&.name).should eq(["画像10.jpg", "画像2.jpg", "画像1.jpg"])
    end
  end
end
