require "json"

# Standalone service for extracting AI generation metadata from image files.
# Not integrated into application routes — designed for future API exposure.
#
# Usage:
#   meta = ImageMetadataService.extract("/path/to/image.png")
#   meta.try(&.to_json)
module ImageMetadataService
  PNG_SIGNATURE = Bytes[137, 80, 78, 71, 13, 10, 26, 10]

  struct AiImageMetadata
    include JSON::Serializable

    # Positive prompt text
    getter prompt : String?

    # Negative prompt text (SD/A1111 style)
    getter negative_prompt : String?

    # Generation settings: Steps, Sampler, CFG scale, Seed, etc.
    getter settings : Hash(String, String)

    # Software field from metadata (e.g. "NovelAI")
    getter software : String?

    # Detected generator: "stable-diffusion", "novelai", "comfyui"
    getter source : String?

    # Original raw metadata text (useful for search / tagging)
    getter raw_text : String?

    def initialize(
      @prompt = nil,
      @negative_prompt = nil,
      @settings = Hash(String, String).new,
      @software = nil,
      @source = nil,
      @raw_text = nil
    )
    end

    def ai_generated? : Bool
      !source.nil? || !prompt.nil?
    end
  end

  # Extract AI metadata from a file path.
  # Returns nil if the file is not a supported format or contains no AI metadata.
  def self.extract(path : String) : AiImageMetadata?
    return nil unless File.extname(path).downcase == ".png"
    File.open(path, "rb") { |f| extract_from_io(f) }
  rescue
    nil
  end

  # Extract from an IO object. Used internally and available for testing.
  def self.extract_from_io(io : IO) : AiImageMetadata?
    texts = read_png_text_chunks(io)
    return nil if texts.empty?
    parse_chunks(texts)
  end

  # --- Private helpers -------------------------------------------------------

  private def self.parse_chunks(texts : Hash(String, String)) : AiImageMetadata?
    # Stable Diffusion / AUTOMATIC1111: tEXt "parameters"
    if raw = texts["parameters"]?
      return parse_sd_parameters(raw)
    end

    # NovelAI: tEXt "Software: NovelAI" + "Description: <prompt>"
    if (sw = texts["Software"]?) && sw.downcase.includes?("novelai")
      return AiImageMetadata.new(
        prompt: presence(texts["Description"]?.to_s),
        software: sw,
        source: "novelai",
        raw_text: texts["Description"]?
      )
    end

    # ComfyUI: tEXt/iTXt "prompt" containing JSON node graph
    if (wf = texts["prompt"]?) && wf.starts_with?("{")
      return parse_comfyui_prompt(wf)
    end

    nil
  end

  # Parse AUTOMATIC1111 / SD WebUI parameters text.
  #
  # Format:
  #   <positive prompt lines>
  #   Negative prompt: <negative prompt lines>
  #   Steps: 20, Sampler: DPM++ 2M Karras, CFG scale: 7, Seed: 12345, ...
  private def self.parse_sd_parameters(raw : String) : AiImageMetadata
    prompt_lines = [] of String
    negative_lines = [] of String
    settings = Hash(String, String).new
    state = :prompt

    raw.strip.each_line do |line|
      case state
      when :prompt
        if line.starts_with?("Negative prompt:")
          state = :negative
          neg = line.sub("Negative prompt:", "").strip
          negative_lines << neg unless neg.empty?
        elsif settings_line?(line)
          state = :settings
          parse_settings_into(line, settings)
        else
          prompt_lines << line
        end
      when :negative
        if settings_line?(line)
          state = :settings
          parse_settings_into(line, settings)
        else
          negative_lines << line
        end
      when :settings
        parse_settings_into(line, settings)
      end
    end

    AiImageMetadata.new(
      prompt: presence(prompt_lines.join("\n").strip),
      negative_prompt: presence(negative_lines.join("\n").strip),
      settings: settings,
      source: "stable-diffusion",
      raw_text: raw
    )
  end

  private def self.settings_line?(line : String) : Bool
    !!(line =~ /^(Steps|Sampler|CFG scale|Seed|Size|Model):\s*/)
  end

  # Parse "Key: value, Key: value, ..." into a Hash.
  private def self.parse_settings_into(line : String, settings : Hash(String, String))
    line.split(", ").each do |pair|
      parts = pair.split(": ", 2)
      settings[parts[0].strip] = parts[1].strip if parts.size == 2
    end
  end

  # Parse ComfyUI prompt JSON (node graph) into structured metadata.
  # Locates the KSampler node, follows its positive/negative/model edges,
  # and collects LoRA loaders from the full graph.
  private def self.parse_comfyui_prompt(json_str : String) : AiImageMetadata
    nodes = JSON.parse(json_str).as_h
    settings = Hash(String, String).new

    ksampler = comfyui_find_ksampler(nodes)

    positive_text = nil
    negative_text = nil

    if ks = ksampler
      inputs = ks["inputs"]?

      {"Seed" => "seed", "Steps" => "steps", "CFG" => "cfg",
       "Sampler" => "sampler_name", "Scheduler" => "scheduler"}.each do |label, key|
        if v = inputs.try(&.[key]?)
          settings[label] = v.to_s unless v.raw.is_a?(Array)
        end
      end

      if ref = inputs.try(&.["positive"]?.try(&.as_a?))
        positive_text = comfyui_resolve_clip_text(nodes, ref[0].as_s)
      end
      if ref = inputs.try(&.["negative"]?.try(&.as_a?))
        negative_text = comfyui_resolve_clip_text(nodes, ref[0].as_s)
      end
      if ref = inputs.try(&.["model"]?.try(&.as_a?))
        if ckpt = comfyui_resolve_checkpoint(nodes, ref[0].as_s)
          settings["Model"] = ckpt
        end
      end
    end

    loras = comfyui_collect_loras(nodes)
    settings["LoRA"] = loras.join(", ") unless loras.empty?

    AiImageMetadata.new(
      prompt: presence(positive_text.to_s),
      negative_prompt: presence(negative_text.to_s),
      settings: settings,
      source: "comfyui",
      raw_text: json_str
    )
  rescue
    AiImageMetadata.new(source: "comfyui", raw_text: json_str)
  end

  private def self.comfyui_find_ksampler(nodes : Hash(String, JSON::Any)) : JSON::Any?
    nodes.each_value do |node|
      ct = node["class_type"]?.try(&.as_s?)
      return node if ct == "KSampler" || ct == "KSamplerAdvanced"
    end
    nil
  end

  # Follow a node reference and return the text from a CLIPTextEncode node.
  # Returns nil if the referenced node is not a CLIPTextEncode.
  private def self.comfyui_resolve_clip_text(nodes : Hash(String, JSON::Any), node_id : String) : String?
    node = nodes[node_id]?
    return nil unless node
    return nil unless node["class_type"]?.try(&.as_s?) == "CLIPTextEncode"
    node["inputs"]?.try(&.["text"]?.try(&.as_s?))
  end

  # Walk the model input chain (LoraLoader → LoraLoader → ... → CheckpointLoaderSimple)
  # and return the checkpoint name.
  private def self.comfyui_resolve_checkpoint(nodes : Hash(String, JSON::Any), node_id : String, depth = 0) : String?
    return nil if depth > 20
    node = nodes[node_id]?
    return nil unless node
    case node["class_type"]?.try(&.as_s?)
    when "CheckpointLoaderSimple"
      node["inputs"]?.try(&.["ckpt_name"]?.try(&.as_s?))
    when .try(&.starts_with?("LoraLoader"))
      if ref = node["inputs"]?.try(&.["model"]?.try(&.as_a?))
        comfyui_resolve_checkpoint(nodes, ref[0].as_s, depth + 1)
      end
    end
  end

  # Collect all LoRA names+strengths from the graph.
  private def self.comfyui_collect_loras(nodes : Hash(String, JSON::Any)) : Array(String)
    loras = [] of String
    nodes.each_value do |node|
      next unless node["class_type"]?.try(&.as_s?).try(&.starts_with?("LoraLoader"))
      inputs = node["inputs"]?
      name = inputs.try(&.["lora_name"]?.try(&.as_s?))
      next unless name
      strength = inputs.try(&.["strength_model"]?.try(&.as_f?))
      loras << (strength ? "#{name}(#{strength})" : name)
    end
    loras
  end

  private def self.presence(s : String) : String?
    s.empty? ? nil : s
  end

  # Read all tEXt and iTXt chunks from a PNG IO stream.
  # CRC is not validated (intentionally skipped for performance).
  private def self.read_png_text_chunks(io : IO) : Hash(String, String)
    result = Hash(String, String).new

    sig = Bytes.new(8)
    return result if io.read(sig) < 8
    return result unless sig == PNG_SIGNATURE

    loop do
      len_buf = Bytes.new(4)
      break if io.read(len_buf) < 4
      length = (len_buf[0].to_u32 << 24) | (len_buf[1].to_u32 << 16) |
               (len_buf[2].to_u32 << 8) | len_buf[3].to_u32

      type_buf = Bytes.new(4)
      break if io.read(type_buf) < 4
      chunk_type = String.new(type_buf)

      data = Bytes.new(length)
      io.read_fully(data) if length > 0
      io.skip(4) # CRC

      case chunk_type
      when "tEXt"
        parse_text_chunk(data, result)
      when "iTXt"
        parse_itxt_chunk(data, result)
      when "IEND"
        break
      end
    end

    result
  rescue
    Hash(String, String).new
  end

  # tEXt format: keyword\0text
  private def self.parse_text_chunk(data : Bytes, result : Hash(String, String))
    null_pos = find_null(data, 0)
    return unless null_pos

    keyword = String.new(data[0, null_pos])
    rest = data.size - null_pos - 1
    return if rest < 0
    result[keyword] = String.new(data[null_pos + 1, rest])
  end

  # iTXt format: keyword\0comp_flag\0comp_method\0lang\0trans_keyword\0text
  private def self.parse_itxt_chunk(data : Bytes, result : Hash(String, String))
    pos = 0

    null_pos = find_null(data, pos)
    return unless null_pos
    keyword = String.new(data[pos, null_pos - pos])
    pos = null_pos + 1

    return if pos + 2 > data.size
    compression_flag = data[pos]
    pos += 2 # skip compression_flag + compression_method

    # skip language tag
    null_pos = find_null(data, pos)
    return unless null_pos
    pos = null_pos + 1

    # skip translated keyword
    null_pos = find_null(data, pos)
    return unless null_pos
    pos = null_pos + 1

    return if pos > data.size
    return unless compression_flag == 0 # skip compressed text

    result[keyword] = String.new(data[pos, data.size - pos])
  end

  private def self.find_null(data : Bytes, from : Int32) : Int32?
    (from...data.size).each do |i|
      return i if data[i] == 0_u8
    end
    nil
  end
end
