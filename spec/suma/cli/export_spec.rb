# frozen_string_literal: true

require "spec_helper"
require "suma/cli/export"
require "fileutils"

RSpec.describe Suma::Cli::Export do
  let(:fixtures_path) { File.join(__dir__, "../../fixtures/extract_terms") }
  let(:manifest_file) { File.join(fixtures_path, "schemas-smrl-all.yml") }
  let(:output_path) do
    File.join(Dir.tmpdir, "suma_export_test_#{Time.now.to_i}")
  end

  after do
    FileUtils.rm_rf(output_path)
    FileUtils.rm_f("#{output_path}.zip")
  end

  describe "#export" do
    context "with valid manifest file" do
      it "exports schemas to directory without annotations" do
        expect do
          described_class.start(["export", "-o", output_path, manifest_file])
        end.not_to raise_error

        expect(File.directory?(output_path)).to be true
        expect(Dir.glob("#{output_path}/**/*.exp")).not_to be_empty
      end

      it "exports schemas with annotations when flag is set" do
        expect do
          described_class.start([
                                  "export",
                                  "-o", output_path,
                                  "--annotations",
                                  manifest_file
                                ])
        end.not_to raise_error

        expect(File.directory?(output_path)).to be true
      end

      it "creates ZIP archive when flag is set" do
        expect do
          described_class.start([
                                  "export",
                                  "-o", output_path,
                                  "--zip",
                                  manifest_file
                                ])
        end.not_to raise_error

        expect(File.directory?(output_path)).to be true
        expect(File.exist?("#{output_path}.zip")).to be true
      end

      it "exports with all options enabled" do
        expect do
          described_class.start([
                                  "export",
                                  "-o", output_path,
                                  "--annotations",
                                  "--zip",
                                  manifest_file
                                ])
        end.not_to raise_error

        expect(File.directory?(output_path)).to be true
        expect(File.exist?("#{output_path}.zip")).to be true
      end
    end

    context "with multiple manifest files" do
      let(:additional_manifest_1) do
        File.join(fixtures_path, "additional-schemas.yml")
      end
      let(:additional_manifest_2) do
        File.join(fixtures_path, "additional-schemas-2.yml")
      end

      it "merges schemas from multiple manifests" do
        expect do
          described_class.start([
                                  "export",
                                  "-o", output_path,
                                  manifest_file,
                                  additional_manifest_1,
                                  additional_manifest_2
                                ])
        end.not_to raise_error

        expect(File.directory?(output_path)).to be true
        exported_files = Dir.glob("#{output_path}/**/*.exp")
        expect(exported_files).not_to be_empty
      end
    end

    context "with independent EXPRESS files" do
      let(:exp_file) do
        File.join(fixtures_path, "resources/action_schema/action_schema.exp")
      end

      it "exports a single independent EXPRESS file" do
        expect do
          described_class.start([
                                  "export",
                                  "-o", output_path,
                                  exp_file
                                ])
        end.not_to raise_error

        expect(File.directory?(output_path)).to be true
        # Plain files should be exported to the root with schema_id.exp
        exported_files = Dir.glob("#{output_path}/*.exp")
        expect(exported_files).not_to be_empty
      end

      it "exports multiple independent EXPRESS files" do
        arm_file = File.join(fixtures_path, "modules/activity/arm.exp")
        mim_file = File.join(fixtures_path, "modules/activity/mim.exp")

        expect do
          described_class.start([
                                  "export",
                                  "-o", output_path,
                                  exp_file,
                                  arm_file,
                                  mim_file
                                ])
        end.not_to raise_error

        expect(File.directory?(output_path)).to be true
        exported_files = Dir.glob("#{output_path}/*.exp")
        expect(exported_files.size).to be >= 3
      end
    end

    context "with mixed manifest and EXP files" do
      let(:exp_file) do
        File.join(fixtures_path, "resources/action_schema/action_schema.exp")
      end

      it "exports both manifest and independent EXPRESS files" do
        expect do
          described_class.start([
                                  "export",
                                  "-o", output_path,
                                  manifest_file,
                                  exp_file
                                ])
        end.not_to raise_error

        expect(File.directory?(output_path)).to be true
        # Should have both categorized schemas from manifest and plain files at root
        all_files = Dir.glob("#{output_path}/**/*.exp")
        expect(all_files).not_to be_empty
      end
    end

    context "with invalid inputs" do
      it "raises error for missing file" do
        expect do
          described_class.start([
                                  "export",
                                  "-o", output_path,
                                  "nonexistent.yml"
                                ])
        end.to raise_error(Errno::ENOENT, /not found/)
      end

      it "raises error for unsupported file type" do
        invalid_file = File.join(fixtures_path, "modules/activity/invalid.txt")
        expect do
          described_class.start([
                                  "export",
                                  "-o", output_path,
                                  invalid_file
                                ])
        end.to raise_error(ArgumentError, /Unsupported file type/)
      end

      it "raises error when output option is missing" do
        expect do
          described_class.start(["export", manifest_file])
        end.to raise_error(SystemExit)
      end

      it "raises error when no files are provided" do
        expect do
          described_class.start(["export", "-o", output_path])
        end.to raise_error(ArgumentError, /At least one file must be specified/)
      end
    end

    context "directory structure" do
      before do
        described_class.start(["export", "-o", output_path, manifest_file])
      end

      it "preserves schema directory structure for manifest files" do
        expect(File.directory?(output_path)).to be true
        # Check for categorized directories
        %w[resources modules].each do |category|
          category_path = File.join(output_path, category)
          next unless Dir.glob("#{fixtures_path}/**/#{category}/**/*.exp").any?

          expect(File.directory?(category_path)).to be true
        end
      end

      it "places manifest schemas in correct categories" do
        resource_schemas = Dir.glob("#{output_path}/resources/**/*.exp")
        module_schemas = Dir.glob("#{output_path}/modules/**/*.exp")

        expect(resource_schemas + module_schemas).not_to be_empty
      end
    end

    context "plain file output structure" do
      let(:exp_file) do
        File.join(fixtures_path, "resources/action_schema/action_schema.exp")
      end

      before do
        described_class.start(["export", "-o", output_path, exp_file])
      end

      it "places independent EXPRESS files directly in output root" do
        expect(File.directory?(output_path)).to be true
        root_files = Dir.glob("#{output_path}/*.exp")
        expect(root_files).not_to be_empty
        # Files should be named {schema_id}.exp
        expect(root_files.first).to match(/action_schema\.exp$/)
      end
    end
  end
end
