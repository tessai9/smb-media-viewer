require "spec"
require "../src/config"

describe AppConfig do
  describe "default values" do
    it "uses /mnt/nas/media as default media_root" do
      config = AppConfig.load("/nonexistent/path_that_does_not_exist.yml")
      config.media_root.should eq("/mnt/nas/media")
    end

    it "uses ~/.cache/media-viewer (expanded) as default cache_dir" do
      config = AppConfig.load("/nonexistent/path_that_does_not_exist.yml")
      # ~ is expanded at load time, so compare against the expanded form
      config.cache_dir.should eq(Path["~/.cache/media-viewer"].expand(home: true).to_s)
    end

    it "uses 3000 as default port" do
      config = AppConfig.load("/nonexistent/path_that_does_not_exist.yml")
      config.port.should eq(3000)
    end

    it "uses 200 as default thumbnail_size" do
      config = AppConfig.load("/nonexistent/path_that_does_not_exist.yml")
      config.thumbnail_size.should eq(200)
    end

    it "uses 50 as default items_per_page" do
      config = AppConfig.load("/nonexistent/path_that_does_not_exist.yml")
      config.items_per_page.should eq(50)
    end
  end

  describe ".load" do
    it "returns defaults when config.yml does not exist" do
      config = AppConfig.load("/nonexistent/config.yml")
      config.port.should eq(3000)
    end

    it "loads port from config file" do
      tmp = File.tempfile("config", ".yml") do |f|
        f.print("port: 8080\n")
      end
      config = AppConfig.load(tmp.path)
      config.port.should eq(8080)
      tmp.delete
    end

    it "loads media_root from config file" do
      tmp = File.tempfile("config", ".yml") do |f|
        f.print("media_root: /my/media\n")
      end
      config = AppConfig.load(tmp.path)
      config.media_root.should eq("/my/media")
      tmp.delete
    end

    it "uses defaults for fields not specified in config file" do
      tmp = File.tempfile("config", ".yml") do |f|
        f.print("port: 9000\n")
      end
      config = AppConfig.load(tmp.path)
      config.port.should eq(9000)
      config.media_root.should eq("/mnt/nas/media")
      config.thumbnail_size.should eq(200)
      config.items_per_page.should eq(50)
      tmp.delete
    end

    it "loads all five config fields" do
      tmp = File.tempfile("config", ".yml") do |f|
        f.print(<<-YAML)
          media_root: /nas/media
          cache_dir: /tmp/cache
          port: 4000
          thumbnail_size: 300
          items_per_page: 100
          YAML
      end
      config = AppConfig.load(tmp.path)
      config.media_root.should eq("/nas/media")
      config.cache_dir.should eq("/tmp/cache")
      config.port.should eq(4000)
      config.thumbnail_size.should eq(300)
      config.items_per_page.should eq(100)
      tmp.delete
    end
  end
end

describe "CONFIG constant" do
  it "is an AppConfig instance" do
    CONFIG.should be_a(AppConfig)
  end

  it "is accessible globally" do
    CONFIG.port.should be_a(Int32)
  end
end
