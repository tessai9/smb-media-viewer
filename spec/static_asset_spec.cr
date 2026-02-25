require "spec"

# Tests for tasks 3.2 (CSS sort-bar) and 3.3 (JS sort params)
# These verify that static assets contain the required sort-related code.

describe "Static Assets" do
  describe "style.css (Task 3.2)" do
    it "contains .sort-bar selector" do
      css = File.read("public/style.css")
      css.should contain(".sort-bar")
    end

    it "is within the 3KB size limit" do
      size = File.size("public/style.css")
      size.should be <= 3072
    end
  end

  describe "app.js (Task 3.3)" do
    it "reads data-sort via dataset.sort" do
      js = File.read("public/app.js")
      js.should contain("dataset.sort")
    end

    it "reads data-order via dataset.order" do
      js = File.read("public/app.js")
      js.should contain("dataset.order")
    end

    it "appends sort and order params to the API fetch URL" do
      js = File.read("public/app.js")
      js.should contain("&sort=")
      js.should contain("&order=")
    end

    it "is within the 8KB size limit" do
      size = File.size("public/app.js")
      size.should be <= 8192
    end
  end
end
