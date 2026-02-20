require "spec"
require "../src/services/mime"

describe MimeService do
  describe ".media_type" do
    # Image extensions
    {"jpg", "jpeg", "png", "gif", "webp", "bmp", "svg"}.each do |ext|
      it "returns Image for .#{ext}" do
        MimeService.media_type("photo.#{ext}").should eq(MediaType::Image)
      end

      it "returns Image for .#{ext.upcase} (case-insensitive)" do
        MimeService.media_type("photo.#{ext.upcase}").should eq(MediaType::Image)
      end
    end

    # Video extensions
    {"mp4", "webm", "mkv", "avi", "mov"}.each do |ext|
      it "returns Video for .#{ext}" do
        MimeService.media_type("video.#{ext}").should eq(MediaType::Video)
      end

      it "returns Video for .#{ext.upcase} (case-insensitive)" do
        MimeService.media_type("video.#{ext.upcase}").should eq(MediaType::Video)
      end
    end

    it "returns Pdf for .pdf" do
      MimeService.media_type("document.pdf").should eq(MediaType::Pdf)
    end

    it "returns Pdf for .PDF (case-insensitive)" do
      MimeService.media_type("document.PDF").should eq(MediaType::Pdf)
    end

    it "returns Unknown for unsupported extension" do
      MimeService.media_type("archive.zip").should eq(MediaType::Unknown)
    end

    it "returns Unknown for file with no extension" do
      MimeService.media_type("README").should eq(MediaType::Unknown)
    end

    it "returns Unknown for hidden files (dot-prefixed)" do
      MimeService.media_type(".hidden").should eq(MediaType::Unknown)
    end
  end

  describe ".content_type" do
    it "returns image/jpeg for .jpg" do
      MimeService.content_type("photo.jpg").should eq("image/jpeg")
    end

    it "returns image/jpeg for .jpeg" do
      MimeService.content_type("photo.jpeg").should eq("image/jpeg")
    end

    it "returns image/png for .png" do
      MimeService.content_type("photo.png").should eq("image/png")
    end

    it "returns image/gif for .gif" do
      MimeService.content_type("photo.gif").should eq("image/gif")
    end

    it "returns image/webp for .webp" do
      MimeService.content_type("photo.webp").should eq("image/webp")
    end

    it "returns image/bmp for .bmp" do
      MimeService.content_type("photo.bmp").should eq("image/bmp")
    end

    it "returns image/svg+xml for .svg" do
      MimeService.content_type("photo.svg").should eq("image/svg+xml")
    end

    it "returns video/mp4 for .mp4" do
      MimeService.content_type("video.mp4").should eq("video/mp4")
    end

    it "returns video/webm for .webm" do
      MimeService.content_type("video.webm").should eq("video/webm")
    end

    it "returns video/x-matroska for .mkv" do
      MimeService.content_type("video.mkv").should eq("video/x-matroska")
    end

    it "returns video/x-msvideo for .avi" do
      MimeService.content_type("video.avi").should eq("video/x-msvideo")
    end

    it "returns video/quicktime for .mov" do
      MimeService.content_type("video.mov").should eq("video/quicktime")
    end

    it "returns application/pdf for .pdf" do
      MimeService.content_type("document.pdf").should eq("application/pdf")
    end

    it "returns application/octet-stream for unknown extensions" do
      MimeService.content_type("archive.zip").should eq("application/octet-stream")
    end

    it "is case-insensitive for content type lookup" do
      MimeService.content_type("photo.JPG").should eq("image/jpeg")
    end
  end

  describe ".supported?" do
    it "returns true for supported image extensions" do
      MimeService.supported?("photo.jpg").should be_true
      MimeService.supported?("photo.png").should be_true
      MimeService.supported?("photo.svg").should be_true
    end

    it "returns true for supported video extensions" do
      MimeService.supported?("video.mp4").should be_true
      MimeService.supported?("video.mkv").should be_true
    end

    it "returns true for .pdf" do
      MimeService.supported?("document.pdf").should be_true
    end

    it "returns false for unsupported extensions" do
      MimeService.supported?("archive.zip").should be_false
      MimeService.supported?("data.csv").should be_false
      MimeService.supported?("script.sh").should be_false
    end

    it "returns false for hidden files (dot-prefixed name)" do
      MimeService.supported?(".hidden").should be_false
    end

    it "returns false for files with no extension" do
      MimeService.supported?("Makefile").should be_false
    end

    it "is case-insensitive" do
      MimeService.supported?("photo.JPG").should be_true
      MimeService.supported?("video.MP4").should be_true
      MimeService.supported?("doc.PDF").should be_true
    end
  end
end
