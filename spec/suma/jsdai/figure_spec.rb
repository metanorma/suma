# frozen_string_literal: true

require "spec_helper"

RSpec.describe Suma::Jsdai::Figure do
  describe "XML parsing and round-trip" do
    it "parses action_schemaexpg1.xml correctly" do
      xml_file = "spec/fixtures/jsdai/resource-action_schema-1/input/action_schemaexpg1.xml"
      image_file = "spec/fixtures/jsdai/resource-action_schema-1/input/action_schemaexpg1.gif"

      figure = described_class.new(xml_file, image_file)

      expect(figure.xml).to be_a(Suma::Jsdai::FigureXml)
      expect(figure.xml.module).to eq("fundamentals_of_product_description_and_support")
      expect(figure.xml.file).to eq("action_schemaexpg1.xml")
      expect(figure.xml.img.src).to eq("action_schemaexpg1.gif")
      expect(figure.xml.img.areas.count).to eq(3)
    end

    it "parses action_schemaexpg2.xml correctly" do
      xml_file = "spec/fixtures/jsdai/resource-action_schema-2/input/action_schemaexpg2.xml"
      image_file = "spec/fixtures/jsdai/resource-action_schema-2/input/action_schemaexpg2.gif"

      figure = described_class.new(xml_file, image_file)

      expect(figure.xml).to be_a(Suma::Jsdai::FigureXml)
      expect(figure.xml.module).to eq("fundamentals_of_product_description_and_support")
      expect(figure.xml.file).to eq("action_schemaexpg2.xml")
      expect(figure.xml.img.src).to eq("action_schemaexpg2.gif")
      expect(figure.xml.img.areas.count).to eq(54)
    end

    it "round-trips XML correctly" do
      xml_file = "spec/fixtures/jsdai/resource-action_schema-1/input/action_schemaexpg1.xml"
      image_file = "spec/fixtures/jsdai/resource-action_schema-1/input/action_schemaexpg1.gif"

      original_xml = File.read(xml_file)
      figure = described_class.new(xml_file, image_file)
      regenerated_xml = figure.xml.to_xml

      # Parse both and compare structure
      original_parsed = Suma::Jsdai::FigureXml.from_xml(original_xml)
      regenerated_parsed = Suma::Jsdai::FigureXml.from_xml(regenerated_xml)

      expect(regenerated_parsed.module).to eq(original_parsed.module)
      expect(regenerated_parsed.file).to eq(original_parsed.file)
      expect(regenerated_parsed.img.src).to eq(original_parsed.img.src)
      expect(regenerated_parsed.img.areas.count).to eq(original_parsed.img.areas.count)
    end
  end

  describe "#to_svg" do
    it "generates SVG for action_schemaexpg1" do
      xml_file = "spec/fixtures/jsdai/resource-action_schema-1/input/action_schemaexpg1.xml"
      image_file = "spec/fixtures/jsdai/resource-action_schema-1/input/action_schemaexpg1.gif"

      figure = described_class.new(xml_file, image_file)
      svg_output = figure.to_svg

      expect(svg_output).to include('<?xml version="1.0" encoding="UTF-8"?>')
      expect(svg_output).to include("<svg")
      expect(svg_output).to include("xmlns=\"http://www.w3.org/2000/svg\"")
      expect(svg_output).to include("<image href=\"data:image/gif;base64,")
      expect(svg_output).to include("<a href=\"1\">")
      expect(svg_output).to include("<rect")
      expect(svg_output).to include("</svg>")

      # Check that we have the right number of clickable areas
      expect(svg_output.scan("<a href=").count).to eq(3)
    end

    it "generates SVG for action_schemaexpg2" do
      xml_file = "spec/fixtures/jsdai/resource-action_schema-2/input/action_schemaexpg2.xml"
      image_file = "spec/fixtures/jsdai/resource-action_schema-2/input/action_schemaexpg2.gif"

      figure = described_class.new(xml_file, image_file)
      svg_output = figure.to_svg

      expect(svg_output).to include('<?xml version="1.0" encoding="UTF-8"?>')
      expect(svg_output).to include("<svg")
      expect(svg_output).to include("xmlns=\"http://www.w3.org/2000/svg\"")
      expect(svg_output).to include("<image href=\"data:image/gif;base64,")

      # Check that we have the right number of clickable areas
      expect(svg_output.scan("<a href=").count).to eq(54)
    end

    it "generates correct rect coordinates from coords" do
      xml_file = "spec/fixtures/jsdai/resource-action_schema-1/input/action_schemaexpg1.xml"
      image_file = "spec/fixtures/jsdai/resource-action_schema-1/input/action_schemaexpg1.gif"

      figure = described_class.new(xml_file, image_file)
      svg_output = figure.to_svg

      # First area coords="210,186,343,227"
      # Should generate: x="210" y="186" width="133" height="41"
      expect(svg_output).to include('height="41" width="133" y="186" x="210"')
    end

    it "generates SVG with polygons for module armexpg1" do
      xml_file = "spec/fixtures/jsdai/module-activity-arm-1/input/armexpg1.xml"
      image_file = "spec/fixtures/jsdai/module-activity-arm-1/input/armexpg1.gif"

      figure = described_class.new(xml_file, image_file)
      svg_output = figure.to_svg

      expect(svg_output).to include("<polygon")
      expect(svg_output).to include('points="61,0,61,56,175,56,175,0,61,0"')
      expect(svg_output.scan("<a href=").count).to eq(2)
    end

    it "generates SVG for geometric_model_schemaexpg1" do
      xml_file = "spec/fixtures/jsdai/resource-geometric_model_schema-1/input/geometric_model_schemaexpg1.xml"
      image_file = "spec/fixtures/jsdai/resource-geometric_model_schema-1/input/geometric_model_schemaexpg1.gif"

      figure = described_class.new(xml_file, image_file)
      svg_output = figure.to_svg

      expect(svg_output).to include('<?xml version="1.0" encoding="UTF-8"?>')
      expect(svg_output).to include("<svg")
      expect(svg_output).to include("<rect")
      expect(svg_output.scan("<a href=").count).to eq(6)
    end

    it "generates SVG for geometry_schemaexpg1" do
      xml_file = "spec/fixtures/jsdai/resource-geometry_schema-1/input/geometry_schemaexpg1.xml"
      image_file = "spec/fixtures/jsdai/resource-geometry_schema-1/input/geometry_schemaexpg1.gif"

      figure = described_class.new(xml_file, image_file)
      svg_output = figure.to_svg

      expect(svg_output).to include('<?xml version="1.0" encoding="UTF-8"?>')
      expect(svg_output).to include("<svg")
      expect(svg_output).to include("<rect")
      expect(svg_output.scan("<a href=").count).to eq(6)
    end
  end

  describe "#to_exp" do
    it "generates EXP for action_schemaexpg1" do
      xml_file = "spec/fixtures/jsdai/resource-action_schema-1/input/action_schemaexpg1.xml"
      image_file = "spec/fixtures/jsdai/resource-action_schema-1/input/action_schemaexpg1.gif"

      figure = described_class.new(xml_file, image_file)
      exp_output = figure.to_exp

      expect(exp_output).to include('(*"action_schema.__expressg"')
      expect(exp_output).to include("[[action_schema_expg1]]")
      expect(exp_output).to include("[.svgmap]")
      expect(exp_output).to include("image::action_schemaexpg1.svg[]")
      expect(exp_output).to include("<<express:basic_attribute_schema>>; 1")
      expect(exp_output).to include("<<express:action_schema>>; 2")
      expect(exp_output).to include("<<express:support_resource_schema>>; 3")
      expect(exp_output).to end_with("*)\n")
    end

    it "generates EXP for action_schemaexpg2" do
      xml_file = "spec/fixtures/jsdai/resource-action_schema-2/input/action_schemaexpg2.xml"
      image_file = "spec/fixtures/jsdai/resource-action_schema-2/input/action_schemaexpg2.gif"

      figure = described_class.new(xml_file, image_file)
      exp_output = figure.to_exp

      expect(exp_output).to include('(*"action_schema.__expressg"')
      expect(exp_output).to include("[[action_schema_expg2]]")
      expect(exp_output).to include("[.svgmap]")
      expect(exp_output).to include("image::action_schemaexpg2.svg[]")
      expect(exp_output).to include("<<express:action_schema.as_name_attribute_select>>; 1")
      expect(exp_output).to include("<<express:action_schema.executed_action>>; 54")
      expect(exp_output).to end_with("*)\n")
    end

    it "generates EXP for module armexpg1" do
      xml_file = "spec/fixtures/jsdai/module-activity-arm-1/input/armexpg1.xml"
      image_file = "spec/fixtures/jsdai/module-activity-arm-1/input/armexpg1.gif"

      figure = described_class.new(xml_file, image_file)
      exp_output = figure.to_exp

      expect(exp_output).to include('(*"Activity_arm.__expressg"')
      expect(exp_output).to include("[[Activity_arm_expg1]]")
      expect(exp_output).to include("<<Activity_method_arm_expg1>>; 1")
      expect(exp_output).to include("<<Activity_arm_expg2>>; 2")
      expect(exp_output).to end_with("*)\n")
    end

    it "generates SVG with polygons for armexpg1" do
      xml_file = "spec/fixtures/jsdai/module-activity-arm-1/input/armexpg1.xml"
      image_file = "spec/fixtures/jsdai/module-activity-arm-1/input/armexpg1.gif"

      figure = described_class.new(xml_file, image_file)
      svg_output = figure.to_svg

      expect(svg_output).to include("<polygon")
      expect(svg_output).to include('points="61,0,61,56,175,56,175,0,61,0"')
      expect(svg_output.scan("<a href=").count).to eq(2)
    end

    it "generates EXP for module mimexpg1" do
      xml_file = "spec/fixtures/jsdai/module-activity-mim-2/input/mimexpg1.xml"
      image_file = "spec/fixtures/jsdai/module-activity-mim-2/input/mimexpg1.gif"

      figure = described_class.new(xml_file, image_file)
      exp_output = figure.to_exp

      expect(exp_output).to include('(*"Activity_mim.__expressg"')
      expect(exp_output).to include("[[Activity_mim_expg1]]")
      expect(exp_output).to end_with("*)\n")
    end

    it "generates EXP for resource geometric_model_schemaexpg1" do
      xml_file = "spec/fixtures/jsdai/resource-geometric_model_schema-1/input/geometric_model_schemaexpg1.xml"
      image_file = "spec/fixtures/jsdai/resource-geometric_model_schema-1/input/geometric_model_schemaexpg1.gif"

      figure = described_class.new(xml_file, image_file)
      exp_output = figure.to_exp

      expect(exp_output).to include('(*"geometric_model_schema.__expressg"')
      expect(exp_output).to include("[[geometric_model_schema_expg1]]")
      expect(exp_output).to include("<<express:measure_schema>>; 1")
      expect(exp_output).to include("<<express:topology_schema>>; 6")
      expect(exp_output).to end_with("*)\n")
    end

    it "generates EXP for resource geometry_schemaexpg1" do
      xml_file = "spec/fixtures/jsdai/resource-geometry_schema-1/input/geometry_schemaexpg1.xml"
      image_file = "spec/fixtures/jsdai/resource-geometry_schema-1/input/geometry_schemaexpg1.gif"

      figure = described_class.new(xml_file, image_file)
      exp_output = figure.to_exp

      expect(exp_output).to include('(*"geometry_schema.__expressg"')
      expect(exp_output).to include("[[geometry_schema_expg1]]")
      expect(exp_output).to include("<<express:topology_schema>>; 1")
      expect(exp_output).to include("<<express:scan_data_3d_shape_model_schema>>; 6")
      expect(exp_output).to end_with("*)\n")
    end
  end
end
