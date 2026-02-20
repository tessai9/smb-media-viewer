require "spec"
require "../src/services/file_browser"

describe FileBrowser do
  describe ".safe_path" do
    root = "/mnt/media"

    it "returns the root path for an empty relative path" do
      result = FileBrowser.safe_path(root, "")
      result.should eq("/mnt/media")
    end

    it "returns absolute path for a simple relative path" do
      result = FileBrowser.safe_path(root, "photos")
      result.should eq("/mnt/media/photos")
    end

    it "returns absolute path for a nested relative path" do
      result = FileBrowser.safe_path(root, "photos/2024/img.jpg")
      result.should eq("/mnt/media/photos/2024/img.jpg")
    end

    it "resolves harmless .. that stays within media_root" do
      result = FileBrowser.safe_path(root, "photos/../videos")
      result.should eq("/mnt/media/videos")
    end

    it "returns nil for .. that escapes media_root" do
      result = FileBrowser.safe_path(root, "../etc/passwd")
      result.should be_nil
    end

    it "returns nil for deep .. traversal that escapes media_root" do
      result = FileBrowser.safe_path(root, "../../etc/passwd")
      result.should be_nil
    end

    it "returns nil for .. that goes exactly to root parent" do
      result = FileBrowser.safe_path(root, "..")
      result.should be_nil
    end

    it "returns nil for absolute path pointing outside media_root" do
      result = FileBrowser.safe_path(root, "/etc/passwd")
      result.should be_nil
    end

    it "returns nil for absolute path to /etc" do
      result = FileBrowser.safe_path(root, "/etc")
      result.should be_nil
    end

    it "handles media_root with trailing slash correctly" do
      result = FileBrowser.safe_path("/mnt/media/", "photos")
      result.should eq("/mnt/media/photos")
    end

    it "returns nil for path that only starts with the same prefix but is outside" do
      # /mnt/media-other should NOT be considered inside /mnt/media
      result = FileBrowser.safe_path("/mnt/media", "../media-other/secret")
      result.should be_nil
    end

    it "returns the root when rel_path is a single dot" do
      result = FileBrowser.safe_path(root, ".")
      result.should eq("/mnt/media")
    end

    it "normalizes redundant separators" do
      result = FileBrowser.safe_path(root, "photos//2024")
      result.should eq("/mnt/media/photos/2024")
    end
  end
end
