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

    it "is under 8KB" do
      File.size(js_path).should be < 8192
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

    it "injects overlay DOM with required element IDs" do
      content = File.read(js_path)
      content.should contain("overlay-img")
      content.should contain("overlay-name")
      content.should contain("overlay-close")
      content.should contain("overlay-prev")
      content.should contain("overlay-next")
    end

    it "sets dataset.mediaType on non-directory cards in buildCard" do
      content = File.read(js_path)
      content.should contain("dataset.mediaType")
      content.should contain("media_type")
    end

    it "opens video cards in a new tab" do
      content = File.read(js_path)
      content.should contain("window.open")
      content.should contain("_blank")
    end

    it "intercepts image card clicks to open the overlay" do
      content = File.read(js_path)
      content.should contain("openOverlay")
      content.should contain("closest")
    end

    it "defines openOverlay that records scroll position and pushes history" do
      content = File.read(js_path)
      content.should contain("function openOverlay")
      content.should contain("window.scrollY")
      content.should contain("history.pushState")
      content.should contain("overlay-open")
    end

    it "defines closeOverlay that restores scroll and pops history" do
      content = File.read(js_path)
      content.should contain("function closeOverlay")
      content.should contain("window.scrollTo")
      content.should contain("history.back")
    end

    it "closes overlay on popstate (browser back button)" do
      content = File.read(js_path)
      content.should contain("popstate")
    end

    it "closes overlay when backdrop is clicked" do
      content = File.read(js_path)
      content.should contain("e.target")
    end

    it "defines getImageCards using live DOM query for image cards" do
      content = File.read(js_path)
      content.should contain("getImageCards")
      content.should contain("data-media-type=\"image\"")
    end

    it "defines showFile that updates overlay content and calls replaceState" do
      content = File.read(js_path)
      content.should contain("function showFile")
      content.should contain("replaceState")
    end

    it "updateNavButtons sets disabled state on prev and next buttons" do
      content = File.read(js_path)
      content.should contain(".disabled")
    end

    it "wires prev and next button click handlers for in-overlay navigation" do
      content = File.read(js_path)
      content.should contain("oPrev")
      content.should contain("oNext")
      (content.includes?("oPrev.addEventListener") || content.includes?("overlay-prev")).should be_true
    end

    it "adds a keydown listener on document for keyboard navigation" do
      content = File.read(js_path)
      content.should contain("keydown")
      content.should contain("document.addEventListener")
    end

    it "handles ArrowRight, ArrowLeft, and Escape keys" do
      content = File.read(js_path)
      content.should contain("ArrowRight")
      content.should contain("ArrowLeft")
      content.should contain("Escape")
    end

    it "calls preventDefault for keyboard events while overlay is open" do
      content = File.read(js_path)
      content.should contain("preventDefault")
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
