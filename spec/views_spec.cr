require "spec"
require "ecr"
require "../src/services/file_browser"
require "../src/services/mime"

describe "layout.ecr" do
  it "renders complete HTML shell" do
    title   = "Test Page"
    content = "<p>inner content here</p>"
    result  = ECR.render("src/views/layout.ecr")
    result.should contain("<!DOCTYPE html>")
    result.should contain("<html")
    result.should contain("inner content here")
    result.should contain("/style.css")
    result.should contain("/app.js")
  end

  it "includes a nav link to the root browse page" do
    title   = "Test"
    content = ""
    result  = ECR.render("src/views/layout.ecr")
    result.should contain("href=\"/browse/\"")
  end

  it "uses the title variable in the <title> tag" do
    title   = "My Custom Title"
    content = ""
    result  = ECR.render("src/views/layout.ecr")
    result.should contain("My Custom Title")
  end
end

describe "directory.ecr" do
  # sort_key and sort_dir are now required by directory.ecr; use defaults for these tests
  sort_key = uninitialized SortKey
  sort_dir = uninitialized SortDir

  before_each do
    sort_key = SortKey::Name
    sort_dir = SortDir::Asc
  end

  it "renders img with src='' and data-src for lazy loading" do
    entries      = [FileEntry.new("photo.jpg", "sub/photo.jpg", false, 1024i64, Time.utc, "image")] of FileEntry
    current_path = "sub"
    result = ECR.render("src/views/directory.ecr")
    result.should contain("src=\"\"")
    result.should contain("data-src=\"/thumbnail/sub/photo.jpg\"")
  end

  it "renders directory entries as /browse/ links" do
    entries      = [FileEntry.new("subdir", "subdir", true, 0i64, Time.utc, "unknown")] of FileEntry
    current_path = ""
    result = ECR.render("src/views/directory.ecr")
    result.should contain("href=\"/browse/subdir\"")
  end

  it "renders file entries as /view/ links" do
    entries      = [FileEntry.new("clip.mp4", "clip.mp4", false, 2048i64, Time.utc, "video")] of FileEntry
    current_path = ""
    result = ECR.render("src/views/directory.ecr")
    result.should contain("href=\"/view/clip.mp4\"")
  end

  it "includes sentinel element for infinite scroll" do
    entries      = [] of FileEntry
    current_path = ""
    result = ECR.render("src/views/directory.ecr")
    result.should contain("id=\"sentinel\"")
  end

  it "sets data-offset to entries count for JS pagination" do
    entries = [
      FileEntry.new("a.jpg", "a.jpg", false, 1i64, Time.utc, "image"),
      FileEntry.new("b.jpg", "b.jpg", false, 2i64, Time.utc, "image"),
      FileEntry.new("c.jpg", "c.jpg", false, 3i64, Time.utc, "image"),
    ] of FileEntry
    current_path = ""
    result = ECR.render("src/views/directory.ecr")
    result.should contain("data-offset=\"3\"")
  end

  it "embeds current_path in data-path attribute for JS" do
    entries      = [] of FileEntry
    current_path = "photos/2024"
    result = ECR.render("src/views/directory.ecr")
    result.should contain("data-path=\"photos/2024\"")
  end

  it "does not render <img> for directory entries" do
    entries      = [FileEntry.new("subdir", "subdir", true, 0i64, Time.utc, "unknown")] of FileEntry
    current_path = ""
    result = ECR.render("src/views/directory.ecr")
    result.should_not contain("data-src=\"/thumbnail/subdir\"")
  end
end

describe "viewer.ecr" do
  it "renders <img> for image media type" do
    entry      = FileEntry.new("photo.jpg", "photos/photo.jpg", false, 1024i64, Time.utc, "image")
    prev_entry = nil.as(FileEntry?)
    next_entry = nil.as(FileEntry?)
    result = ECR.render("src/views/viewer.ecr")
    result.should contain("<img")
    result.should contain("/raw/photos/photo.jpg")
  end

  it "renders <video controls> for video media type" do
    entry      = FileEntry.new("clip.mp4", "videos/clip.mp4", false, 1024i64, Time.utc, "video")
    prev_entry = nil.as(FileEntry?)
    next_entry = nil.as(FileEntry?)
    result = ECR.render("src/views/viewer.ecr")
    result.should contain("<video")
    result.should contain("controls")
    result.should contain("/raw/videos/clip.mp4")
  end

  it "renders <object> and <a download> fallback for PDF" do
    entry      = FileEntry.new("doc.pdf", "docs/doc.pdf", false, 1024i64, Time.utc, "pdf")
    prev_entry = nil.as(FileEntry?)
    next_entry = nil.as(FileEntry?)
    result = ECR.render("src/views/viewer.ecr")
    result.should contain("<object")
    result.should contain("/raw/docs/doc.pdf")
    result.should contain("download")
  end

  it "renders prev and next navigation links when available" do
    entry      = FileEntry.new("b.jpg", "b.jpg", false, 1024i64, Time.utc, "image")
    prev_entry = FileEntry.new("a.jpg", "a.jpg", false, 1024i64, Time.utc, "image").as(FileEntry?)
    next_entry = FileEntry.new("c.jpg", "c.jpg", false, 1024i64, Time.utc, "image").as(FileEntry?)
    result = ECR.render("src/views/viewer.ecr")
    result.should contain("/view/a.jpg")
    result.should contain("/view/c.jpg")
  end

  it "does not render prev/next links when both are nil" do
    entry      = FileEntry.new("photo.jpg", "photo.jpg", false, 1024i64, Time.utc, "image")
    prev_entry = nil.as(FileEntry?)
    next_entry = nil.as(FileEntry?)
    result = ECR.render("src/views/viewer.ecr")
    result.should_not contain("/view/")
  end

  it "links back to the parent directory in browse" do
    entry      = FileEntry.new("photo.jpg", "photos/photo.jpg", false, 1024i64, Time.utc, "image")
    prev_entry = nil.as(FileEntry?)
    next_entry = nil.as(FileEntry?)
    result = ECR.render("src/views/viewer.ecr")
    result.should contain("href=\"/browse/photos\"")
  end

  it "links back to root /browse/ when file is in root directory" do
    entry      = FileEntry.new("photo.jpg", "photo.jpg", false, 1024i64, Time.utc, "image")
    prev_entry = nil.as(FileEntry?)
    next_entry = nil.as(FileEntry?)
    result = ECR.render("src/views/viewer.ecr")
    result.should contain("href=\"/browse/\"")
  end
end
