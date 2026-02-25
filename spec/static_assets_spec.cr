require "./spec_helper"

describe "Static Assets" do
  describe "public/style.css" do
    css_path = File.join(__DIR__, "..", "public", "style.css")

    it "exists in the public directory" do
      File.exists?(css_path).should be_true
    end

    it "is under 3KB" do
      File.size(css_path).should be < 3072
    end

    it "implements CSS Grid for the thumbnail grid" do
      content = File.read(css_path)
      (content.includes?("display:grid") || content.includes?("display: grid")).should be_true
    end

    it "includes .grid, .card, and .navbar selectors" do
      content = File.read(css_path)
      content.should contain(".grid")
      content.should contain(".card")
      content.should contain(".navbar")
    end

    it "includes a dark background colour" do
      content = File.read(css_path)
      # Expect a dark hex colour on body or a variable assignment
      (content.includes?("#111") || content.includes?("#0") || content.includes?("rgb(") || content.includes?("--bg")).should be_true
    end

    it "includes a responsive @media query" do
      content = File.read(css_path)
      content.should contain("@media")
    end

    it "includes .viewer selector for the viewer page layout" do
      content = File.read(css_path)
      content.should contain(".viewer")
    end

    it "includes #overlay selector with fixed positioning" do
      content = File.read(css_path)
      content.should contain("#overlay")
      (content.includes?("position:fixed") || content.includes?("position: fixed")).should be_true
    end

    it "includes body.overlay-open rule to lock background scroll" do
      content = File.read(css_path)
      content.should contain("body.overlay-open")
      (content.includes?("overflow:hidden") || content.includes?("overflow: hidden")).should be_true
    end

    it "includes #overlay-close selector for the close button" do
      content = File.read(css_path)
      content.should contain("#overlay-close")
    end

    it "includes prev and next button selectors" do
      content = File.read(css_path)
      content.should contain("#overlay-prev")
      content.should contain("#overlay-next")
    end

    it "includes #overlay-name selector for the filename label" do
      content = File.read(css_path)
      content.should contain("#overlay-name")
    end
  end

  describe "public/app.js" do
    js_path = File.join(__DIR__, "..", "public", "app.js")

    it "exists in the public directory" do
      File.exists?(js_path).should be_true
    end

    it "is under 4KB" do
      File.size(js_path).should be < 4096
    end

    it "uses IntersectionObserver" do
      content = File.read(js_path)
      content.should contain("IntersectionObserver")
    end

    it "implements lazy loading via data-src attribute" do
      content = File.read(js_path)
      content.should contain("data-src")
    end

    it "includes a fallback for browsers without IntersectionObserver" do
      content = File.read(js_path)
      content.should contain("typeof IntersectionObserver")
    end

    it "uses fetch for infinite scroll API calls" do
      content = File.read(js_path)
      content.should contain("fetch(")
    end

    it "targets the /api/files/ endpoint" do
      content = File.read(js_path)
      content.should contain("/api/files/")
    end
  end

  describe "public/no-thumbnail.svg" do
    svg_path = File.join(__DIR__, "..", "public", "no-thumbnail.svg")

    it "exists in the public directory" do
      File.exists?(svg_path).should be_true
    end

    it "is a valid SVG file" do
      content = File.read(svg_path)
      content.should contain("<svg")
      content.should contain("</svg>")
    end

    it "is small enough for efficient delivery (under 2KB)" do
      File.size(svg_path).should be < 2048
    end

    it "has correct viewBox for square thumbnail display" do
      content = File.read(svg_path)
      content.should contain("viewBox")
    end
  end
end
