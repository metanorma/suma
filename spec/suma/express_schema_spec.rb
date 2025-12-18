# frozen_string_literal: true

require "suma/express_schema"
require "fileutils"
require "tmpdir"

RSpec.describe Suma::ExpressSchema do
  let(:temp_dir) { Dir.mktmpdir }
  let(:output_path) { File.join(temp_dir, "plain_schemas", "modules") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#build_output_filename" do
    context "when processing manifest schemas (is_standalone_file: false)" do
      context "with module schemas" do
        it "preserves original directory structure for arm.exp files" do
          schema = described_class.new(
            id: "Geometric_tolerance_arm",
            path: "schemas/modules/geometric_tolerance/arm.exp",
            output_path: output_path,
            is_standalone_file: false,
          )

          expected_path = File.join(
            output_path,
            "geometric_tolerance",
            "arm.exp",
          )
          expect(schema.filename_plain).to eq(expected_path)
        end

        it "preserves original directory structure for mim.exp files" do
          schema = described_class.new(
            id: "Geometric_tolerance_mim",
            path: "schemas/modules/geometric_tolerance/mim.exp",
            output_path: output_path,
            is_standalone_file: false,
          )

          expected_path = File.join(
            output_path,
            "geometric_tolerance",
            "mim.exp",
          )
          expect(schema.filename_plain).to eq(expected_path)
        end

        it "preserves directory structure for activity module" do
          schema = described_class.new(
            id: "Activity_arm",
            path: "schemas/modules/activity/arm.exp",
            output_path: output_path,
            is_standalone_file: false,
          )

          expected_path = File.join(output_path, "activity", "arm.exp")
          expect(schema.filename_plain).to eq(expected_path)
        end
      end

      context "with resource schemas" do
        let(:output_path_resources) do
          File.join(temp_dir, "plain_schemas", "resources")
        end

        it "preserves original directory structure" do
          schema = described_class.new(
            id: "action_schema",
            path: "schemas/resources/action_schema/action_schema.exp",
            output_path: output_path_resources,
            is_standalone_file: false,
          )

          expected_path = File.join(
            output_path_resources,
            "action_schema",
            "action_schema.exp",
          )
          expect(schema.filename_plain).to eq(expected_path)
        end

        it "handles different resource schema names" do
          schema = described_class.new(
            id: "geometry_schema",
            path: "schemas/resources/geometry_schema/geometry_schema.exp",
            output_path: output_path_resources,
            is_standalone_file: false,
          )

          expected_path = File.join(
            output_path_resources,
            "geometry_schema",
            "geometry_schema.exp",
          )
          expect(schema.filename_plain).to eq(expected_path)
        end
      end

      context "with absolute paths" do
        it "still extracts the correct parent directory" do
          absolute_path = File.expand_path(
            "schemas/modules/geometric_tolerance/arm.exp",
          )
          schema = described_class.new(
            id: "Geometric_tolerance_arm",
            path: absolute_path,
            output_path: output_path,
            is_standalone_file: false,
          )

          expected_path = File.join(
            output_path,
            "geometric_tolerance",
            "arm.exp",
          )
          expect(schema.filename_plain).to eq(expected_path)
        end
      end
    end

    context "when processing standalone schemas (is_standalone_file: true)" do
      it "outputs directly to output_path with schema ID as filename" do
        schema = described_class.new(
          id: "my_schema",
          path: "some/path/to/schema.exp",
          output_path: output_path,
          is_standalone_file: true,
        )

        expected_path = File.join(output_path, "my_schema.exp")
        expect(schema.filename_plain).to eq(expected_path)
      end

      it "uses schema ID regardless of source filename" do
        schema = described_class.new(
          id: "custom_id",
          path: "different/path/original_name.exp",
          output_path: output_path,
          is_standalone_file: true,
        )

        expected_path = File.join(output_path, "custom_id.exp")
        expect(schema.filename_plain).to eq(expected_path)
      end
    end
  end

  describe "#type" do
    it "identifies resource schemas" do
      schema = described_class.new(
        id: "action_schema",
        path: "schemas/resources/action_schema/action_schema.exp",
        output_path: output_path,
      )

      expect(schema.type).to eq("resources")
    end

    it "identifies module schemas" do
      schema = described_class.new(
        id: "Activity_arm",
        path: "schemas/modules/activity/arm.exp",
        output_path: output_path,
      )

      expect(schema.type).to eq("modules")
    end

    it "returns unknown_type for unrecognized paths" do
      schema = described_class.new(
        id: "custom",
        path: "some/custom/path/schema.exp",
        output_path: output_path,
      )

      expect(schema.type).to eq("unknown_type")
    end
  end

  describe "regression test for issue #78" do
    it "does not use schema ID as directory name" do
      # This is the exact scenario from issue #78
      schema = described_class.new(
        id: "Geometric_tolerance_arm",
        path: "schemas/modules/geometric_tolerance/arm.exp",
        output_path: output_path,
        is_standalone_file: false,
      )

      result = schema.filename_plain

      # Should NOT contain the schema ID in the path
      expect(result).not_to include("Geometric_tolerance_arm")

      # Should preserve the original directory name
      expect(result).to include("geometric_tolerance")

      # Should have the correct full path
      expected = File.join(output_path, "geometric_tolerance", "arm.exp")
      expect(result).to eq(expected)
    end

    it "ensures collection.yml paths match actual output for modules" do
      # Test the exact scenario that breaks Metanorma builds
      arm_schema = described_class.new(
        id: "Geometric_tolerance_arm",
        path: "schemas/modules/geometric_tolerance/arm.exp",
        output_path: output_path,
        is_standalone_file: false,
      )

      mim_schema = described_class.new(
        id: "Geometric_tolerance_mim",
        path: "schemas/modules/geometric_tolerance/mim.exp",
        output_path: output_path,
        is_standalone_file: false,
      )

      # Both should be in the same directory
      arm_dir = File.dirname(arm_schema.filename_plain)
      mim_dir = File.dirname(mim_schema.filename_plain)
      expect(arm_dir).to eq(mim_dir)

      # Directory should match the source directory name
      expect(File.basename(arm_dir)).to eq("geometric_tolerance")
    end
  end

  describe "regression test for PR #23" do
    it "preserves original filename instead of using schema ID" do
      # PR #23 fixed the filename to use File.basename(@path) instead of "#{id}.exp"
      schema = described_class.new(
        id: "Geometric_tolerance_arm",
        path: "schemas/modules/geometric_tolerance/arm.exp",
        output_path: output_path,
        is_standalone_file: false,
      )

      result = schema.filename_plain

      # Filename should be from source path (arm.exp), not schema ID
      expect(File.basename(result)).to eq("arm.exp")
      expect(File.basename(result)).not_to eq("Geometric_tolerance_arm.exp")
    end

    it "works for mim files as well" do
      schema = described_class.new(
        id: "Geometric_tolerance_mim",
        path: "schemas/modules/geometric_tolerance/mim.exp",
        output_path: output_path,
        is_standalone_file: false,
      )

      result = schema.filename_plain

      # Filename should be mim.exp, not Geometric_tolerance_mim.exp
      expect(File.basename(result)).to eq("mim.exp")
      expect(File.basename(result)).not_to eq("Geometric_tolerance_mim.exp")
    end

    it "preserves filename for arm_lf files" do
      schema = described_class.new(
        id: "Ap210_electronic_assembly_arm_lf",
        path: "schemas/modules/ap210_electronic/arm_lf.exp",
        output_path: output_path,
        is_standalone_file: false,
      )

      result = schema.filename_plain

      # Should preserve arm_lf.exp, not use schema ID
      expect(File.basename(result)).to eq("arm_lf.exp")
    end
  end
end