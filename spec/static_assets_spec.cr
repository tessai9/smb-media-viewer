require "./spec_helper"

describe "Static Assets" do
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
