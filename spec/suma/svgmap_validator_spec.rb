# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# The source-layer svgmap gate (TRThurman, iso-10303#875): a schema's
# `__expressg` [.svgmap] block binds its ordinal markers to the SVG's
# anchor-wrapped shapes. A marker without a shape, a shape no entry
# covers, or a missing image produces a hotspot that can never bind -
# the class the site gate counts only after a full render. This
# validator states the contract at the source, per schema.
RSpec.describe Suma::SvgmapValidator do
  def write(path, content)
    path.dirname.mkpath
    path.write(content)
  end

  def exp_source(svg_name)
    <<~EXP
      (*"demo_schema.__expressg"
      [[demo_schema_expg1]]
      [.svgmap]
      ====
      image::#{svg_name}[]

      * <<express:alpha_schema>>; 1
      * <<express:demo_schema>>; 2
      ====

      *)
      SCHEMA demo_schema;
      END_SCHEMA;
    EXP
  end

  def svg(shapes)
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg">
      #{shapes.map { |m| "<a href=\"#{m}\"><rect/></a>" }.join("\n")}
      </svg>
    SVG
  end

  def validate(root)
    manifest = root / "schemas.yaml"
    write(manifest, <<~YAML)
      schemas:
        demo_schema:
          path: schemas/demo_schema.exp
    YAML
    described_class.new.validate_manifest(manifest.to_s)
  end

  it "passes a block whose markers match the SVG's wrapped shapes" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      write(root / "schemas/demo_schema.exp", exp_source("demo.expg1.svg"))
      write(root / "schemas/demo.expg1.svg", svg(%w[1 2]))

      result = validate(root)

      expect(result.checked_schemas).to eq 1
      expect(result.checked_blocks).to eq 1
      expect(result.violations).to be_empty
    end
  end

  it "reports a marker with no wrapped shape and a shape no entry covers" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      write(root / "schemas/demo_schema.exp", exp_source("demo.expg1.svg"))
      write(root / "schemas/demo.expg1.svg", svg(%w[1 2 3]))

      result = validate(root)

      types = result.violations.to_h { |v| [v.type, v.detail] }
      expect(types.keys).to contain_exactly("unlisted_shape")
      expect(types["unlisted_shape"]).to eq("3")
    end
  end

  it "reports a missing_shape when the SVG lacks a listed marker" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      write(root / "schemas/demo_schema.exp", exp_source("demo.expg1.svg"))
      write(root / "schemas/demo.expg1.svg", svg(%w[1]))

      result = validate(root)

      expect(result.violations.map(&:type)).to eq(["missing_shape"])
      expect(result.violations.first.detail).to eq("2")
    end
  end

  it "reports a missing image and skips its marker contract" do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      write(root / "schemas/demo_schema.exp",
            exp_source("nowhere.expg1.svg"))

      result = validate(root)

      expect(result.violations.map(&:type)).to eq(["missing_image"])
      expect(result.violations.first.detail).to eq("nowhere.expg1.svg")
    end
  end
end
