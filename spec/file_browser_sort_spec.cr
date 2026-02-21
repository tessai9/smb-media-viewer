require "spec"
require "file_utils"
require "../src/services/file_browser"

# Helper: create a temp directory with known files/dirs, run block, then clean up.
# Directory structure:
#   aaaa_dir/   (directory)
#   zzzz_dir/   (directory)
#   alpha.jpg   mtime=2023-01-01
#   beta.jpg    mtime=2024-01-01
#   gamma.jpg   mtime=2025-01-01
private def with_sort_test_dir(&block : String ->)
  tmpdir = File.join(Dir.tempdir, "mv_sort_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(tmpdir)
  Dir.mkdir_p(File.join(tmpdir, "aaaa_dir"))
  Dir.mkdir_p(File.join(tmpdir, "zzzz_dir"))

  # Create files
  ["alpha.jpg", "beta.jpg", "gamma.jpg"].each do |f|
    File.write(File.join(tmpdir, f), "x")
  end

  # Set deterministic mtimes via File.utime(atime, mtime, path)
  t_old  = Time.utc(2023, 1, 1)
  t_mid  = Time.utc(2024, 1, 1)
  t_new  = Time.utc(2025, 1, 1)
  File.utime(t_old, t_old, File.join(tmpdir, "alpha.jpg"))
  File.utime(t_mid, t_mid, File.join(tmpdir, "beta.jpg"))
  File.utime(t_new, t_new, File.join(tmpdir, "gamma.jpg"))

  begin
    block.call(tmpdir)
  ensure
    FileUtils.rm_rf(tmpdir)
  end
end

# ----- Task 1.1: parse_sort_key / parse_sort_dir -----

describe "FileBrowser.parse_sort_key" do
  it "returns Name for 'name'" do
    FileBrowser.parse_sort_key("name").should eq(SortKey::Name)
  end

  it "returns Ctime for 'ctime'" do
    FileBrowser.parse_sort_key("ctime").should eq(SortKey::Ctime)
  end

  it "returns Mtime for 'mtime'" do
    FileBrowser.parse_sort_key("mtime").should eq(SortKey::Mtime)
  end

  it "returns Name for an invalid value" do
    FileBrowser.parse_sort_key("size").should eq(SortKey::Name)
  end

  it "returns Name for an empty string" do
    FileBrowser.parse_sort_key("").should eq(SortKey::Name)
  end
end

describe "FileBrowser.parse_sort_dir" do
  it "returns Asc for 'asc'" do
    FileBrowser.parse_sort_dir("asc").should eq(SortDir::Asc)
  end

  it "returns Desc for 'desc'" do
    FileBrowser.parse_sort_dir("desc").should eq(SortDir::Desc)
  end

  it "returns Asc for an invalid value" do
    FileBrowser.parse_sort_dir("up").should eq(SortDir::Asc)
  end

  it "returns Asc for an empty string" do
    FileBrowser.parse_sort_dir("").should eq(SortDir::Asc)
  end
end

# ----- Task 1.2: FileEntry has ctime field -----

describe "FileEntry.ctime" do
  it "has a ctime field that is not serialized to JSON" do
    entry = FileEntry.new(
      name:       "test.jpg",
      path:       "test.jpg",
      is_dir:     false,
      size:       0i64,
      mtime:      Time.utc(2024, 1, 1),
      media_type: "image",
      ctime:      Time.utc(2023, 6, 1)
    )
    entry.ctime.should eq(Time.utc(2023, 6, 1))
    # ctime must NOT appear in JSON output
    json = entry.to_json
    json.should_not contain("ctime")
  end
end

# ----- Task 1.3: list_entries with sort params -----

describe "FileBrowser.list_entries — sort_key=Name" do
  it "sorts files A→Z (ascending)" do
    with_sort_test_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Asc)
      entries.should_not be_nil
      file_names = entries.not_nil!.reject(&.is_dir).map(&.name)
      file_names.should eq(["alpha.jpg", "beta.jpg", "gamma.jpg"])
    end
  end

  it "sorts files Z→A (descending)" do
    with_sort_test_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Desc)
      entries.should_not be_nil
      file_names = entries.not_nil!.reject(&.is_dir).map(&.name)
      file_names.should eq(["gamma.jpg", "beta.jpg", "alpha.jpg"])
    end
  end

  it "sorts directories A→Z (ascending)" do
    with_sort_test_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Asc)
      entries.should_not be_nil
      dir_names = entries.not_nil!.select(&.is_dir).map(&.name)
      dir_names.should eq(["aaaa_dir", "zzzz_dir"])
    end
  end

  it "sorts directories Z→A (descending)" do
    with_sort_test_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Desc)
      entries.should_not be_nil
      dir_names = entries.not_nil!.select(&.is_dir).map(&.name)
      dir_names.should eq(["zzzz_dir", "aaaa_dir"])
    end
  end
end

describe "FileBrowser.list_entries — sort_key=Mtime" do
  it "sorts files oldest→newest (ascending)" do
    with_sort_test_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Mtime, SortDir::Asc)
      entries.should_not be_nil
      file_names = entries.not_nil!.reject(&.is_dir).map(&.name)
      file_names.should eq(["alpha.jpg", "beta.jpg", "gamma.jpg"])
    end
  end

  it "sorts files newest→oldest (descending)" do
    with_sort_test_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Mtime, SortDir::Desc)
      entries.should_not be_nil
      file_names = entries.not_nil!.reject(&.is_dir).map(&.name)
      file_names.should eq(["gamma.jpg", "beta.jpg", "alpha.jpg"])
    end
  end
end

describe "FileBrowser.list_entries — sort_key=Ctime" do
  it "returns results without error (ctime available via File::Info)" do
    with_sort_test_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Ctime, SortDir::Asc)
      entries.should_not be_nil
      entries.not_nil!.size.should eq(5)  # 2 dirs + 3 files
    end
  end
end

describe "FileBrowser.list_entries — directories always before files" do
  it "dirs precede files with sort_key=Name asc" do
    with_sort_test_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Asc)
      entries.should_not be_nil
      all = entries.not_nil!
      first_file_idx = all.index { |e| !e.is_dir }
      last_dir_idx   = all.rindex { |e| e.is_dir }
      # All dirs must come before all files
      (last_dir_idx.not_nil! < first_file_idx.not_nil!).should be_true
    end
  end

  it "dirs precede files with sort_key=Mtime desc" do
    with_sort_test_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Mtime, SortDir::Desc)
      entries.should_not be_nil
      all = entries.not_nil!
      first_file_idx = all.index { |e| !e.is_dir }
      last_dir_idx   = all.rindex { |e| e.is_dir }
      (last_dir_idx.not_nil! < first_file_idx.not_nil!).should be_true
    end
  end

  it "dirs precede files with sort_key=Ctime asc" do
    with_sort_test_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Ctime, SortDir::Asc)
      entries.should_not be_nil
      all = entries.not_nil!
      first_file_idx = all.index { |e| !e.is_dir }
      last_dir_idx   = all.rindex { |e| e.is_dir }
      (last_dir_idx.not_nil! < first_file_idx.not_nil!).should be_true
    end
  end
end

describe "FileBrowser.list_entries — backward compatibility (no sort params)" do
  it "uses Name/Asc as default when called without sort params" do
    with_sort_test_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100)
      entries.should_not be_nil
      file_names = entries.not_nil!.reject(&.is_dir).map(&.name)
      file_names.should eq(["alpha.jpg", "beta.jpg", "gamma.jpg"])
    end
  end
end

describe "FileBrowser.list_entries — offset/limit paging with sort" do
  it "returns correct page slice from sorted list" do
    with_sort_test_dir do |tmpdir|
      # Full sorted list (Name/Asc): aaaa_dir, zzzz_dir, alpha.jpg, beta.jpg, gamma.jpg
      # offset=2, limit=2 → [alpha.jpg, beta.jpg]
      entries = FileBrowser.list_entries(tmpdir, "", 2, 2, SortKey::Name, SortDir::Asc)
      entries.should_not be_nil
      entries.not_nil!.map(&.name).should eq(["alpha.jpg", "beta.jpg"])
    end
  end

  it "returns empty array when offset is beyond sorted list end" do
    with_sort_test_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 100, 10, SortKey::Name, SortDir::Asc)
      entries.should_not be_nil
      entries.not_nil!.should be_empty
    end
  end
end
