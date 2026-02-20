require "spec"
require "file_utils"
require "../src/services/file_browser"

# Helper: create a temp directory, yield it, then clean up.
private def with_test_dir(&block : String ->)
  tmpdir = File.join(Dir.tempdir, "mv_test_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(tmpdir)
  begin
    block.call(tmpdir)
  ensure
    FileUtils.rm_rf(tmpdir)
  end
end

describe FileBrowser do
  describe ".list_entries (filtering & sorting)" do
    it "returns an empty array for an empty directory" do
      with_test_dir do |root|
        result = FileBrowser.list_entries(root, "", 0, 100)
        result.should_not be_nil
        result.not_nil!.should be_empty
      end
    end

    it "returns nil for a path that escapes media_root" do
      with_test_dir do |root|
        FileBrowser.list_entries(root, "../../etc", 0, 100).should be_nil
      end
    end

    it "excludes hidden files (dot-prefixed names)" do
      with_test_dir do |root|
        File.write(File.join(root, ".hidden"), "")
        File.write(File.join(root, ".dotfile.jpg"), "")
        result = FileBrowser.list_entries(root, "", 0, 100).not_nil!
        result.map(&.name).should_not contain(".hidden")
        result.map(&.name).should_not contain(".dotfile.jpg")
      end
    end

    it "excludes unsupported file types" do
      with_test_dir do |root|
        File.write(File.join(root, "archive.zip"), "")
        File.write(File.join(root, "script.sh"), "")
        File.write(File.join(root, "readme.txt"), "")
        result = FileBrowser.list_entries(root, "", 0, 100).not_nil!
        names = result.map(&.name)
        names.should_not contain("archive.zip")
        names.should_not contain("script.sh")
        names.should_not contain("readme.txt")
      end
    end

    it "always includes directories even if they have unsupported-looking names" do
      with_test_dir do |root|
        Dir.mkdir(File.join(root, "photos"))
        Dir.mkdir(File.join(root, "archive.zip"))  # directory named like an archive
        result = FileBrowser.list_entries(root, "", 0, 100).not_nil!
        names = result.map(&.name)
        names.should contain("photos")
        names.should contain("archive.zip")
      end
    end

    it "includes supported media files" do
      with_test_dir do |root|
        File.write(File.join(root, "photo.jpg"), "")
        File.write(File.join(root, "clip.mp4"), "")
        File.write(File.join(root, "doc.pdf"), "")
        result = FileBrowser.list_entries(root, "", 0, 100).not_nil!
        names = result.map(&.name)
        names.should contain("photo.jpg")
        names.should contain("clip.mp4")
        names.should contain("doc.pdf")
      end
    end

    it "sorts directories before files" do
      with_test_dir do |root|
        File.write(File.join(root, "alpha.jpg"), "")
        Dir.mkdir(File.join(root, "zdir"))
        result = FileBrowser.list_entries(root, "", 0, 100).not_nil!
        dir_idx  = result.index { |e| e.name == "zdir" }.not_nil!
        file_idx = result.index { |e| e.name == "alpha.jpg" }.not_nil!
        dir_idx.should be < file_idx
      end
    end

    it "sorts directories alphabetically (case-insensitive)" do
      with_test_dir do |root|
        Dir.mkdir(File.join(root, "Zoo"))
        Dir.mkdir(File.join(root, "alpha"))
        Dir.mkdir(File.join(root, "Beta"))
        result = FileBrowser.list_entries(root, "", 0, 100).not_nil!
        dirs = result.select(&.is_dir).map(&.name)
        dirs.should eq(["alpha", "Beta", "Zoo"])
      end
    end

    it "sorts files alphabetically (case-insensitive)" do
      with_test_dir do |root|
        File.write(File.join(root, "Zebra.jpg"), "")
        File.write(File.join(root, "apple.jpg"), "")
        File.write(File.join(root, "Mango.jpg"), "")
        result = FileBrowser.list_entries(root, "", 0, 100).not_nil!
        files = result.reject(&.is_dir).map(&.name)
        files.should eq(["apple.jpg", "Mango.jpg", "Zebra.jpg"])
      end
    end

    it "sets is_dir correctly" do
      with_test_dir do |root|
        File.write(File.join(root, "photo.jpg"), "")
        Dir.mkdir(File.join(root, "subdir"))
        result = FileBrowser.list_entries(root, "", 0, 100).not_nil!
        result.find { |e| e.name == "subdir" }.not_nil!.is_dir.should be_true
        result.find { |e| e.name == "photo.jpg" }.not_nil!.is_dir.should be_false
      end
    end

    it "sets size 0 for directories" do
      with_test_dir do |root|
        Dir.mkdir(File.join(root, "subdir"))
        result = FileBrowser.list_entries(root, "", 0, 100).not_nil!
        result.find { |e| e.name == "subdir" }.not_nil!.size.should eq(0i64)
      end
    end

    it "sets correct media_type string for each file type" do
      with_test_dir do |root|
        File.write(File.join(root, "photo.jpg"), "")
        File.write(File.join(root, "clip.mp4"), "")
        File.write(File.join(root, "doc.pdf"), "")
        Dir.mkdir(File.join(root, "folder"))
        result = FileBrowser.list_entries(root, "", 0, 100).not_nil!
        find = ->(n : String) { result.find { |e| e.name == n }.not_nil! }
        find.call("photo.jpg").media_type.should eq("image")
        find.call("clip.mp4").media_type.should eq("video")
        find.call("doc.pdf").media_type.should eq("pdf")
        find.call("folder").media_type.should eq("unknown")
      end
    end

    it "sets path as relative from media_root" do
      with_test_dir do |root|
        File.write(File.join(root, "photo.jpg"), "")
        result = FileBrowser.list_entries(root, "", 0, 100).not_nil!
        result.first.path.should eq("photo.jpg")
      end
    end

    it "sets path as relative from media_root for nested entries" do
      with_test_dir do |root|
        Dir.mkdir(File.join(root, "sub"))
        File.write(File.join(root, "sub", "photo.jpg"), "")
        result = FileBrowser.list_entries(root, "sub", 0, 100).not_nil!
        result.first.path.should eq("sub/photo.jpg")
      end
    end

    it "lists contents of a subdirectory" do
      with_test_dir do |root|
        Dir.mkdir(File.join(root, "photos"))
        File.write(File.join(root, "photos", "img.png"), "")
        result = FileBrowser.list_entries(root, "photos", 0, 100).not_nil!
        result.map(&.name).should contain("img.png")
      end
    end
  end
end
