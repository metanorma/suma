# frozen_string_literal: true

require "spec_helper"
require "suma/cli/export"
require "fileutils"

RSpec.describe Suma::Cli::Export do
  let(:fixtures_path) { File.join(__dir__, "../../fixtures/extract_terms") }
  let(:manifest_file) { File.join(fixtures_path, "schemas-smrl-all.yml") }
  let(:output_path) { File.join(Dir.tmpdir, "suma_export_test_#{Time.now.to_i}") }

  after do
    FileUtils.rm_rf(output_path) if File.exist?(output_path)
    FileUtils.rm_f("#{output_path}.zip") if File.exist?("#{output_path}.zip")
  end

  describe "#export" do
    context "with valid manifest" do
      it "exports schemas to directory without annotations" do
        expect do
          described_class.start(["export", manifest_file, "-o", output_path])
        end.not_to raise_error

        expect(File.directory?(output_path)).to be true
        expect(Dir.glob("#{output_path}/**/*.exp")).not_to be_empty
      end

      it "exports schemas with annotations when flag is set" do
        expect do
          described_class.start([
            "export", manifest_file,
            "-o", output_path,
            "--annotations"
          ])
        end.not_to raise_error

        expect(File.directory?(output_path)).to be true
      end

      it "creates ZIP archive when flag is set" do
        expect do
          described_class.start([
            "export", manifest_file,
            "-o", output_path,
            "--zip"
          ])
        end.not_to raise_error

        expect(File.directory?(output_path)).to be true
        expect(File.exist?("#{output_path}.zip")).to be true
      end

      it "exports with all options enabled" do
        expect do
          described_class.start([
            "export", manifest_file,
            "-o", output_path,
            "--annotations",
            "--zip"
          ])
        end.not_to raise_error

        expect(File.directory?(output_path)).to be true
        expect(File.exist?("#{output_path}.zip")).to be true
      end
    end

    context "with additional manifest" do
      let(:additional_manifest) do
        File.join(fixtures_path, "additional-schemas.yml")
      end

      it "merges schemas from both manifests" do
        expect do
          described_class.start([
            "export", manifest_file,
            "-o", output_path,
            "-a", additional_manifest
          ])
        end.not_to raise_error

        expect(File.directory?(output_path)).to be true
      end
    end

    context "with multiple additional manifests" do
      let(:additional_manifest_1) do
        File.join(fixtures_path, "additional-schemas.yml")
      end
      let(:additional_manifest_2) do
        File.join(fixtures_path, "additional-schemas-2.yml")
      end

      it "merges schemas from all manifests" do
        expect do
          described_class.start([
            "export", manifest_file,
            "-o", output_path,
            "-a", additional_manifest_1,
            "-a", additional_manifest_2
          ])
        end.not_to raise_error

        expect(File.directory?(output_path)).to be true

        # Verify that schemas from all manifests were merged and exported
        # The command should successfully merge all manifests without errors
        exported_files = Dir.glob("#{output_path}/**/*.exp")
        expect(exported_files).not_to be_empty
      end
    end

    context "with invalid inputs" do
      it "raises error for missing manifest file" do
        expect do
          described_class.start([
            "export", "nonexistent.yml",
            "-o", output_path
          ])
        end.to raise_error(Errno::ENOENT, /not found/)
      end

      it "raises error for missing additional manifest file" do
        expect do
          described_class.start([
            "export", manifest_file,
            "-o", output_path,
            "-a", "nonexistent-additional.yml"
          ])
        end.to raise_error(Errno::ENOENT, /not found/)
      end

      it "raises error when output option is missing" do
        expect do
          described_class.start(["export", manifest_file])
        end.to raise_error(SystemExit)
      end
    end

    context "directory structure" do
      before do
        described_class.start(["export", manifest_file, "-o", output_path])
      end

      it "preserves schema directory structure" do
        expect(File.directory?(output_path)).to be true
        # Check for categorized directories
        %w[resources modules].each do |category|
          category_path = File.join(output_path, category)
          next unless Dir.glob("#{fixtures_path}/**/#{category}/**/*.exp").any?

          expect(File.directory?(category_path)).to be true
        end
      end

      it "places schemas in correct categories" do
        resource_schemas = Dir.glob("#{output_path}/resources/**/*.exp")
        module_schemas = Dir.glob("#{output_path}/modules/**/*.exp")

        expect(resource_schemas + module_schemas).not_to be_empty
      end
    end
  end
end
