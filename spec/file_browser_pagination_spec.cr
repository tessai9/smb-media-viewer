require "spec"
require "file_utils"
require "../src/services/file_browser"

# Creates a temp directory with `n` image files named 01.jpg .. n.jpg
# plus an optional subdirectory "aaa" (sorts first).
private def with_paged_dir(count : Int32, &block : String ->)
  tmpdir = File.join(Dir.tempdir, "mv_page_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(tmpdir)
  count.times do |i|
    File.write(File.join(tmpdir, "%02d.jpg" % (i + 1)), "")
  end
  begin
    block.call(tmpdir)
  ensure
    FileUtils.rm_rf(tmpdir)
  end
end

describe FileBrowser do
  describe ".list_entries (pagination)" do
    it "returns first `limit` entries when offset=0" do
      with_paged_dir(10) do |root|
        result = FileBrowser.list_entries(root, "", 0, 3).not_nil!
        result.size.should eq(3)
        result.first.name.should eq("01.jpg")
      end
    end

    it "skips `offset` entries" do
      with_paged_dir(10) do |root|
        result = FileBrowser.list_entries(root, "", 3, 3).not_nil!
        result.size.should eq(3)
        result.first.name.should eq("04.jpg")
      end
    end

    it "returns remaining entries when offset+limit exceeds total" do
      with_paged_dir(5) do |root|
        result = FileBrowser.list_entries(root, "", 3, 10).not_nil!
        result.size.should eq(2)
        result.first.name.should eq("04.jpg")
        result.last.name.should eq("05.jpg")
      end
    end

    it "returns empty array when offset equals total count" do
      with_paged_dir(5) do |root|
        result = FileBrowser.list_entries(root, "", 5, 10).not_nil!
        result.should be_empty
      end
    end

    it "returns empty array when offset exceeds total count" do
      with_paged_dir(5) do |root|
        result = FileBrowser.list_entries(root, "", 99, 10).not_nil!
        result.should be_empty
      end
    end

    it "clamps limit to 100 when limit > 100" do
      with_paged_dir(150) do |root|
        result = FileBrowser.list_entries(root, "", 0, 200).not_nil!
        result.size.should eq(100)
      end
    end

    it "clamps limit=101 to 100" do
      with_paged_dir(150) do |root|
        result = FileBrowser.list_entries(root, "", 0, 101).not_nil!
        result.size.should eq(100)
      end
    end

    it "allows limit=100 without clamping" do
      with_paged_dir(150) do |root|
        result = FileBrowser.list_entries(root, "", 0, 100).not_nil!
        result.size.should eq(100)
      end
    end

    it "returns all entries when total < limit (no clamping needed)" do
      with_paged_dir(5) do |root|
        result = FileBrowser.list_entries(root, "", 0, 50).not_nil!
        result.size.should eq(5)
      end
    end

    it "pages correctly through all entries with multiple calls" do
      with_paged_dir(7) do |root|
        page1 = FileBrowser.list_entries(root, "", 0, 3).not_nil!
        page2 = FileBrowser.list_entries(root, "", 3, 3).not_nil!
        page3 = FileBrowser.list_entries(root, "", 6, 3).not_nil!
        page1.size.should eq(3)
        page2.size.should eq(3)
        page3.size.should eq(1)
        all_names = (page1 + page2 + page3).map(&.name)
        all_names.should eq((1..7).map { |i| "%02d.jpg" % i })
      end
    end
  end
end
