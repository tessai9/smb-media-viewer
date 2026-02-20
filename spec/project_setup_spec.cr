require "./spec_helper"

describe "Project Setup" do
  it "has src/services directory" do
    Dir.exists?(File.join(__DIR__, "..", "src", "services")).should be_true
  end

  it "has src/views directory" do
    Dir.exists?(File.join(__DIR__, "..", "src", "views")).should be_true
  end

  it "has public directory" do
    Dir.exists?(File.join(__DIR__, "..", "public")).should be_true
  end

  it "has shard.yml with kemal as the only shard dependency" do
    content = File.read(File.join(__DIR__, "..", "shard.yml"))
    content.should contain("kemal")
  end
end
