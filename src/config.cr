require "yaml"

struct AppConfig
  include YAML::Serializable

  property media_root     : String = "/mnt/nas/media"
  property cache_dir      : String = "~/.cache/media-viewer"
  property port           : Int32  = 3000
  property thumbnail_size : Int32  = 200
  property items_per_page : Int32  = 50

  # Load config from a YAML file. Returns defaults if the file does not exist.
  def self.load(path : String = "config.yml") : AppConfig
    if File.exists?(path)
      AppConfig.from_yaml(File.read(path))
    else
      AppConfig.from_yaml("{}")
    end
  rescue ex : Exception
    STDERR.puts "Config load error (#{path}): #{ex.message}"
    AppConfig.from_yaml("{}")
  end
end

# Load once at startup; remains constant for the lifetime of the process.
CONFIG = AppConfig.load
