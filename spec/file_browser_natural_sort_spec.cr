require "spec"
require "file_utils"
require "../src/services/file_browser"

# Helper: temp directory with files named to trigger numeric ordering differences.
# Creates image1.jpg, image2.jpg, image10.jpg — current lexicographic sort
# produces [image1, image10, image2]; natural sort must give [image1, image2, image10].
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

describe "FileBrowser.list_entries — natural sort (Name key)" do
  it "sorts files with a numeric suffix in numeric order ascending" do
    with_numeric_sort_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Asc)
      entries.not_nil!.map(&.name).should eq(["image1.jpg", "image2.jpg", "image10.jpg"])
    end
  end

  it "sorts files with a numeric suffix in numeric order descending" do
    with_numeric_sort_dir do |tmpdir|
      entries = FileBrowser.list_entries(tmpdir, "", 0, 100, SortKey::Name, SortDir::Desc)
      entries.not_nil!.map(&.name).should eq(["image10.jpg", "image2.jpg", "image1.jpg"])
    end
  end
end
