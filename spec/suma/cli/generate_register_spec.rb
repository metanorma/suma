# frozen_string_literal: true

require "spec_helper"
require "suma/cli/generate_register"
require "tmpdir"
require "tempfile"

RSpec.describe Suma::Cli::GenerateRegister do
  let(:test_output_path) { Dir.mktmpdir }
  let(:test_subject) { described_class.new }

  let(:manifest_file) do
    file = Tempfile.new(["schemas", ".yml"])
    file.write(YAML.dump(
                 "schemas" => {
                   "topology_schema" => {
                     "path" => "schemas/resources/topology_schema/topology_schema.exp",
                   },
                 },
               ))
    file.close
    file.path
  end

  after do
    FileUtils.rm_rf(test_output_path)
    FileUtils.rm_f(manifest_file)
  end

  context "when input is invalid" do
    it "raises ENOENT when manifest file not found" do
      expect do
        test_subject.invoke(
          :generate_register,
          ["not-found.yml", test_output_path],
          {
            urn: "urn:iso:std:iso:10303:-2:ed-2:en:tech:*",
            id: "iso10303-2-express",
            ref: "ISO 10303-2 EXPRESS Concepts",
          },
        )
      end.to raise_error(Errno::ENOENT)
    end
  end

  context "when input is valid" do
    it "writes register.yaml to the output directory" do
      test_subject.invoke(
        :generate_register,
        [manifest_file, test_output_path],
        {
          urn: "urn:iso:std:iso:10303:-2:ed-2:en:tech:*",
          id: "iso10303-2-express",
          ref: "ISO 10303-2 EXPRESS Concepts",
        },
      )
      expect(File).to exist(File.join(test_output_path, "register.yaml"))
    end

    it "passes the owner option through to the generator" do
      test_subject.invoke(
        :generate_register,
        [manifest_file, test_output_path],
        {
          urn: "urn:iso:std:iso:10303:-2:ed-2:en:tech:*",
          id: "iso10303-2-express",
          ref: "ISO 10303-2 EXPRESS Concepts",
          owner: "Custom Owner",
        },
      )
      content = File.read(File.join(test_output_path, "register.yaml"))
      expect(content).to include("owner: Custom Owner")
    end
  end
end
