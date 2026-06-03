require "spec"
require "file_utils"
require "../src/services/image_metadata"

# ---------------------------------------------------------------------------
# PNG test fixture builder
# Produces a minimal PNG (signature + optional tEXt/iTXt chunks + IEND).
# CRC fields are set to dummy zeros — the parser intentionally skips CRC.
# ---------------------------------------------------------------------------

private def write_png_chunk(buf : IO::Memory, type : String, data : Bytes)
  length = data.size.to_u32
  buf.write_byte((length >> 24).to_u8)
  buf.write_byte((length >> 16).to_u8)
  buf.write_byte((length >> 8).to_u8)
  buf.write_byte(length.to_u8)
  buf.write(type.to_slice[0, 4])
  buf.write(data) if data.size > 0
  buf.write(Bytes[0, 0, 0, 0]) # dummy CRC
end

private def build_test_png(
  text_chunks : Hash(String, String) = {} of String => String,
  itxt_chunks : Hash(String, String) = {} of String => String
) : Bytes
  buf = IO::Memory.new

  # PNG signature
  buf.write(Bytes[137, 80, 78, 71, 13, 10, 26, 10])

  text_chunks.each do |keyword, text|
    data = IO::Memory.new
    data.write(keyword.to_slice)
    data.write_byte(0_u8)
    data.write(text.to_slice)
    write_png_chunk(buf, "tEXt", data.to_slice)
  end

  itxt_chunks.each do |keyword, text|
    data = IO::Memory.new
    data.write(keyword.to_slice)
    data.write_byte(0_u8) # keyword null terminator
    data.write_byte(0_u8) # compression flag = 0 (uncompressed)
    data.write_byte(0_u8) # compression method
    data.write_byte(0_u8) # language tag (empty, null terminated)
    data.write_byte(0_u8) # translated keyword (empty, null terminated)
    data.write(text.to_slice)
    write_png_chunk(buf, "iTXt", data.to_slice)
  end

  write_png_chunk(buf, "IEND", Bytes.new(0))
  buf.to_slice
end

private def with_tmpdir(&block : String ->)
  dir = File.join(Dir.tempdir, "img_meta_test_#{Random.rand(1_000_000)}")
  Dir.mkdir_p(dir)
  begin
    block.call(dir)
  ensure
    FileUtils.rm_rf(dir)
  end
end

# ---------------------------------------------------------------------------
# Specs
# ---------------------------------------------------------------------------

describe ImageMetadataService do
  describe ".extract" do
    it "returns nil for non-PNG files" do
      with_tmpdir do |dir|
        path = File.join(dir, "photo.jpg")
        File.write(path, "not a png")
        ImageMetadataService.extract(path).should be_nil
      end
    end

    it "returns nil for a non-existent file" do
      ImageMetadataService.extract("/nonexistent/image.png").should be_nil
    end

    it "returns nil for a PNG with no AI metadata" do
      with_tmpdir do |dir|
        path = File.join(dir, "plain.png")
        File.write(path, build_test_png, mode: "wb")
        ImageMetadataService.extract(path).should be_nil
      end
    end

    it "returns nil for a PNG with unrelated tEXt chunks" do
      with_tmpdir do |dir|
        path = File.join(dir, "comment.png")
        File.write(path, build_test_png({"Comment" => "hello"}), mode: "wb")
        ImageMetadataService.extract(path).should be_nil
      end
    end

    context "Stable Diffusion / AUTOMATIC1111 format" do
      sd_params = "1girl, solo, blue eyes, long hair, masterpiece, best quality\nNegative prompt: nsfw, ugly, blurry, bad anatomy\nSteps: 20, Sampler: DPM++ 2M Karras, CFG scale: 7, Seed: 987654321, Size: 512x768, Model: dreamshaper_8"

      it "sets source to stable-diffusion" do
        with_tmpdir do |dir|
          path = File.join(dir, "sd.png")
          File.write(path, build_test_png({"parameters" => sd_params}), mode: "wb")
          meta = ImageMetadataService.extract(path).not_nil!
          meta.source.should eq("stable-diffusion")
        end
      end

      it "extracts the positive prompt" do
        with_tmpdir do |dir|
          path = File.join(dir, "sd.png")
          File.write(path, build_test_png({"parameters" => sd_params}), mode: "wb")
          meta = ImageMetadataService.extract(path).not_nil!
          meta.prompt.not_nil!.should contain("1girl")
          meta.prompt.not_nil!.should contain("masterpiece")
        end
      end

      it "extracts the negative prompt" do
        with_tmpdir do |dir|
          path = File.join(dir, "sd.png")
          File.write(path, build_test_png({"parameters" => sd_params}), mode: "wb")
          meta = ImageMetadataService.extract(path).not_nil!
          meta.negative_prompt.not_nil!.should contain("ugly")
          meta.negative_prompt.not_nil!.should contain("blurry")
        end
      end

      it "extracts settings (Steps, Sampler, Seed, etc.)" do
        with_tmpdir do |dir|
          path = File.join(dir, "sd.png")
          File.write(path, build_test_png({"parameters" => sd_params}), mode: "wb")
          meta = ImageMetadataService.extract(path).not_nil!
          meta.settings["Steps"].should eq("20")
          meta.settings["Sampler"].should eq("DPM++ 2M Karras")
          meta.settings["CFG scale"].should eq("7")
          meta.settings["Seed"].should eq("987654321")
        end
      end

      it "sets ai_generated? to true" do
        with_tmpdir do |dir|
          path = File.join(dir, "sd.png")
          File.write(path, build_test_png({"parameters" => sd_params}), mode: "wb")
          meta = ImageMetadataService.extract(path).not_nil!
          meta.ai_generated?.should be_true
        end
      end

      it "stores the original raw_text" do
        with_tmpdir do |dir|
          path = File.join(dir, "sd.png")
          File.write(path, build_test_png({"parameters" => sd_params}), mode: "wb")
          meta = ImageMetadataService.extract(path).not_nil!
          meta.raw_text.should eq(sd_params)
        end
      end

      it "handles missing negative prompt gracefully" do
        params = "portrait, cinematic lighting\nSteps: 30, Sampler: Euler a, CFG scale: 8, Seed: 1"
        with_tmpdir do |dir|
          path = File.join(dir, "no_neg.png")
          File.write(path, build_test_png({"parameters" => params}), mode: "wb")
          meta = ImageMetadataService.extract(path).not_nil!
          meta.prompt.should eq("portrait, cinematic lighting")
          meta.negative_prompt.should be_nil
        end
      end
    end

    context "NovelAI format" do
      it "sets source to novelai" do
        with_tmpdir do |dir|
          path = File.join(dir, "nai.png")
          chunks = {"Software" => "NovelAI", "Description" => "cat girl, detailed, anime style"}
          File.write(path, build_test_png(chunks), mode: "wb")
          meta = ImageMetadataService.extract(path).not_nil!
          meta.source.should eq("novelai")
        end
      end

      it "extracts prompt from Description field" do
        with_tmpdir do |dir|
          path = File.join(dir, "nai.png")
          chunks = {"Software" => "NovelAI", "Description" => "cat girl, detailed, anime style"}
          File.write(path, build_test_png(chunks), mode: "wb")
          meta = ImageMetadataService.extract(path).not_nil!
          meta.prompt.should eq("cat girl, detailed, anime style")
        end
      end

      it "stores the software field" do
        with_tmpdir do |dir|
          path = File.join(dir, "nai.png")
          chunks = {"Software" => "NovelAI", "Description" => "test"}
          File.write(path, build_test_png(chunks), mode: "wb")
          meta = ImageMetadataService.extract(path).not_nil!
          meta.software.should eq("NovelAI")
        end
      end
    end

    context "ComfyUI format" do
      comfy_workflow = %({"last_node_id":1,"nodes":[{"id":1,"type":"KSampler"}]})

      it "sets source to comfyui" do
        with_tmpdir do |dir|
          path = File.join(dir, "comfy.png")
          File.write(path, build_test_png(itxt_chunks: {"prompt" => comfy_workflow}), mode: "wb")
          meta = ImageMetadataService.extract(path).not_nil!
          meta.source.should eq("comfyui")
        end
      end

      it "stores the workflow JSON as raw_text" do
        with_tmpdir do |dir|
          path = File.join(dir, "comfy.png")
          File.write(path, build_test_png(itxt_chunks: {"prompt" => comfy_workflow}), mode: "wb")
          meta = ImageMetadataService.extract(path).not_nil!
          meta.raw_text.should eq(comfy_workflow)
        end
      end
    end
  end

  describe "AiImageMetadata#to_json" do
    it "serializes all fields to JSON" do
      meta = ImageMetadataService::AiImageMetadata.new(
        prompt: "a beautiful landscape",
        negative_prompt: "blurry",
        settings: {"Steps" => "20", "Seed" => "42"},
        source: "stable-diffusion"
      )
      json = meta.to_json
      json.should contain(%("prompt":"a beautiful landscape"))
      json.should contain(%("source":"stable-diffusion"))
      json.should contain(%("Steps":"20"))
    end

    it "omits null fields cleanly" do
      meta = ImageMetadataService::AiImageMetadata.new(source: "comfyui")
      json = meta.to_json
      json.should contain(%("source":"comfyui"))
    end
  end
end
