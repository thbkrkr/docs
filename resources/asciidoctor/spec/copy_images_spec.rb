require 'copy_images/extension'
require 'fileutils'
require 'tmpdir'

RSpec.describe CopyImages do
  RSpec::Matchers.define_negated_matcher :not_match, :match

  before(:each) do
    Extensions.register do
      tree_processor CopyImages
    end
  end

  after(:each) do
    Extensions.unregister_all
  end

  private
  def copy_attributes copied
    return {
      'copy_image' => Proc.new { |uri, source|
        copied << [uri, source]
      }
    }
  end

  spec_dir = File.dirname(__FILE__)

  it "copies a file when directly referenced" do
    copied = []
    attributes = copy_attributes copied
    input = <<~ASCIIDOC
      == Example
      image::resources/copy_images/example1.png[]
    ASCIIDOC
    convert input, attributes, match(/INFO: <stdin>: line 2: copying resources\/copy_images\/example1.png/)
    expect(copied).to eq([
        ["resources/copy_images/example1.png", "#{spec_dir}/resources/copy_images/example1.png"]
    ])
  end

  it "copies a file when it can be found in a sub tree" do
    copied = []
    attributes = copy_attributes copied
    input = <<~ASCIIDOC
      == Example
      image::example1.png[]
    ASCIIDOC
    convert input, attributes, match(/INFO: <stdin>: line 2: copying example1.png/)
    expect(copied).to eq([
        ["example1.png", "#{spec_dir}/resources/copy_images/example1.png"]
    ])
  end

  it "copies a path when it can be found in a sub tree" do
    copied = []
    attributes = copy_attributes copied
    input = <<~ASCIIDOC
      == Example
      image::copy_images/example1.png[]
    ASCIIDOC
    convert input, attributes, match(/INFO: <stdin>: line 2: copying copy_images\/example1.png/)
    expect(copied).to eq([
        ["copy_images/example1.png", "#{spec_dir}/resources/copy_images/example1.png"]
    ])
  end

  it "warns when it can't find a file" do
    copied = []
    attributes = copy_attributes copied
    input = <<~ASCIIDOC
      == Example
      image::not_found.jpg[]
    ASCIIDOC
    convert input, attributes, match(/
        WARN:\ <stdin>:\ line\ 2:\ can't\ read\ image\ at\ any\ of\ \[
          "#{spec_dir}\/not_found.jpg",\s
          "#{spec_dir}\/resources\/not_found.jpg",\s
          .+
          "#{spec_dir}\/resources\/copy_images\/not_found.jpg"
          .+
        \]/x).and(not_match(/INFO: <stdin>/))
    expect(copied).to eq([])
  end

  it "only attempts to copy each file once" do
    copied = []
    attributes = copy_attributes copied
    input = <<~ASCIIDOC
      == Example
      image::resources/copy_images/example1.png[]
      image::resources/copy_images/example1.png[]
      image::resources/copy_images/example2.png[]
      image::resources/copy_images/example1.png[]
      image::resources/copy_images/example2.png[]
      ASCIIDOC
    convert input, attributes, match(/INFO: <stdin>: line 2: copying resources\/copy_images\/example1.png/).and(
        match(/INFO: <stdin>: line 4: copying resources\/copy_images\/example2.png/))
    expect(copied).to eq([
        ["resources/copy_images/example1.png", "#{spec_dir}/resources/copy_images/example1.png"],
        ["resources/copy_images/example2.png", "#{spec_dir}/resources/copy_images/example2.png"],
    ])
  end

  it "skips external images" do
    copied = []
    attributes = copy_attributes copied
    input = <<~ASCIIDOC
      == Example
      image::https://f.cloud.github.com/assets/4320215/768165/19d8b1aa-e899-11e2-91bc-6b0553e8d722.png[]
      ASCIIDOC
    convert input, attributes
    expect(copied).to eq([])
  end

  it "can find files using a single valued resources attribute" do
    Dir.mktmpdir {|tmp|
      FileUtils.cp(
          ::File.join(spec_dir, 'resources', 'copy_images', 'example1.png'),
          ::File.join(tmp, 'tmp_example1.png')
      )

      copied = []
      attributes = copy_attributes copied
      attributes['resources'] = tmp
      input = <<~ASCIIDOC
        == Example
        image::tmp_example1.png[]
      ASCIIDOC
      # NOCOMMIT full paths in logs too, I think
      convert input, attributes, match(/INFO: <stdin>: line 2: copying tmp_example1.png/)
      expect(copied).to eq([
          ["tmp_example1.png", "#{tmp}/tmp_example1.png"]
      ])
    }
  end

  it "can find files using a multi valued resources attribute" do
    Dir.mktmpdir {|tmp|
      FileUtils.cp(
          ::File.join(spec_dir, 'resources', 'copy_images', 'example1.png'),
          ::File.join(tmp, 'tmp_example1.png')
      )

      copied = []
      attributes = copy_attributes copied
      attributes['resources'] = "dummy1,#{tmp},/dummy2"
      input = <<~ASCIIDOC
        == Example
        image::tmp_example1.png[]
      ASCIIDOC
      convert input, attributes, match(/INFO: <stdin>: line 2: copying tmp_example1.png/)
      expect(copied).to eq([
          ["tmp_example1.png", "#{tmp}/tmp_example1.png"]
      ])
    }
  end

  it "has a nice error message when it can't find a file with single valued resources attribute" do
    Dir.mktmpdir {|tmp|
      copied = []
      attributes = copy_attributes copied
      attributes['resources'] = tmp
      input = <<~ASCIIDOC
        == Example
        image::not_found.png[]
      ASCIIDOC
      convert input, attributes, match(/
          WARN:\ <stdin>:\ line\ 2:\ can't\ read\ image\ at\ any\ of\ \[
            "#{spec_dir}\/not_found.png",\s
            "#{tmp}\/not_found.png"
            .+
          \]/x).and(not_match(/INFO: <stdin>/))
      expect(copied).to eq([])
    }
  end

  it "has a nice error message when it can't find a file with multi valued resources attribute" do
    Dir.mktmpdir {|tmp|
      copied = []
      attributes = copy_attributes copied
      attributes['resources'] = "#{tmp},/dummy2"
      input = <<~ASCIIDOC
        == Example
        image::not_found.png[]
      ASCIIDOC
      convert input, attributes, match(/
          WARN:\ <stdin>:\ line\ 2:\ can't\ read\ image\ at\ any\ of\ \[
            "#{spec_dir}\/not_found.png",\s
            "#{tmp}\/not_found.png",\s
            "\/dummy2\/not_found.png"
            .+
          \]/x).and(not_match(/INFO: <stdin>/))
      expect(copied).to eq([])
    }
  end
end