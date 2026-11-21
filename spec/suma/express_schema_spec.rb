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

      expect(schema.type).to eq(:resource)
    end

    it "identifies module schemas by path" do
      schema = described_class.new(
        id: "Activity",
        path: "schemas/modules/activity/arm.exp",
        output_path: output_path,
      )

      expect(schema.type).to eq(:module_arm)
    end

    it "identifies module_arm by id suffix" do
      schema = described_class.new(
        id: "Activity_arm",
        path: "some/path/schema.exp",
        output_path: output_path,
      )

      expect(schema.type).to eq(:module_arm)
    end

    it "identifies module_mim by id suffix" do
      schema = described_class.new(
        id: "Activity_mim",
        path: "some/path/schema.exp",
        output_path: output_path,
      )

      expect(schema.type).to eq(:module_mim)
    end

    it "identifies business_object_model by id suffix" do
      schema = described_class.new(
        id: "Activity_bom",
        path: "some/path/schema.exp",
        output_path: output_path,
      )

      expect(schema.type).to eq(:business_object_model)
    end

    it "returns standalone for unrecognized paths" do
      schema = described_class.new(
        id: "custom",
        path: "some/custom/path/schema.exp",
        output_path: output_path,
      )

      expect(schema.type).to eq(:standalone)
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

  describe "#to_plain" do
    it "writes the plain form: no tagged description blocks, source comments kept" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "demo.exp")
        File.write(path, <<~EXPRESS)
          (*
          Demo header block.
          *)
          SCHEMA demo_schema;
            (*"demo_schema.entity_one"
            Description block for entity_one.
            *)
            ENTITY entity_one;
              name : STRING;
            END_ENTITY;
          END_SCHEMA; -- demo_schema
        EXPRESS

        schema = described_class.new(
          id: "demo_schema", path: path, output_path: File.join(dir, "out"),
        )
        plain = schema.to_plain

        expect(plain).not_to include("Description block for entity_one")
        expect(plain).to include("ENTITY entity_one;")
        expect(plain).to include("END_SCHEMA;")
        # the pre-SCHEMA header survives verbatim (expressir#696 drops it
        # at parse time; the plain face restores it from the source)
        expect(plain).to include("Demo header block.")
        expect(plain.index("Demo header block."))
          .to be < plain.index("SCHEMA demo_schema;")
      end
    end

    it "keeps a header whose comment body names SCHEMA at line start" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "draft.exp")
        File.write(path, <<~EXPRESS)
          (*
          DRAFT notes.
          made this update
          SCHEMA draft_mim '{iso standard 10303 part(1)}';
          *)
          SCHEMA draft_mim;
          END_SCHEMA;
        EXPRESS

        schema = described_class.new(
          id: "draft_mim", path: path, output_path: File.join(dir, "out"),
        )
        plain = schema.to_plain

        # the whole comment, inner SCHEMA line included, is header; the
        # statement keyword the parser saw is the formatter's body start
        expect(plain.lines.count do |line|
          line.start_with?("SCHEMA draft_mim;")
        end).to eq(1)
        expect(plain).to include("DRAFT notes.")
        expect(plain).to include(
          "SCHEMA draft_mim '{iso standard 10303 part(1)}';"
        )
      end
    end
  end
end
