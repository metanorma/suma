# frozen_string_literal: true

require "suma/svg_quality/scanner"
require "suma/svg_quality/report"
require "suma/svg_quality/batch_report"

RSpec.describe Suma::SvgQuality::Scanner do
  let(:fixtures_root) do
    File.expand_path("../../fixtures/svg_quality", __dir__)
  end

  let(:valid_svg) { File.join(fixtures_root, "valid.svg") }

  describe "#scan_file" do
    it "returns a Report for a single file" do
      report = described_class.new.scan_file(valid_svg)
      expect(report).to be_a(Suma::SvgQuality::Report)
      expect(report.file_path).to eq(valid_svg)
    end

    it "forwards the configured profile to the validator" do
      report = described_class.new(profile: :svg_1_2_rfc).scan_file(valid_svg)
      expect(report.error_count).to be_an(Integer)
    end
  end

  describe "#scan" do
    it "returns an empty BatchReport when no paths are given" do
      batch = described_class.new.scan([])
      expect(batch).to be_a(Suma::SvgQuality::BatchReport)
      expect(batch.total_files).to eq(0)
    end

    it "returns a BatchReport whose size matches the input" do
      batch = described_class.new.scan([valid_svg, valid_svg, valid_svg])
      expect(batch.total_files).to eq(3)
    end

    it "builds each Report with the original file path" do
      batch = described_class.new.scan([valid_svg])
      expect(batch.reports.first.file_path).to eq(valid_svg)
    end

    it "invokes the progress adapter once per file with index and total" do
      recorder = Class.new do
        attr_reader :calls

        def initialize
          @calls = []
        end

        def call(index, total, report)
          @calls << { index: index, total: total, report: report }
        end
      end.new

      described_class.new(progress: recorder).scan([valid_svg, valid_svg])

      expect(recorder.calls.length).to eq(2)
      expect(recorder.calls.first[:index]).to eq(0)
      expect(recorder.calls.first[:total]).to eq(2)
      expect(recorder.calls.last[:index]).to eq(1)
      expect(recorder.calls.first[:report])
        .to be_a(Suma::SvgQuality::Report)
    end

    it "uses NullProgress by default without error" do
      expect { described_class.new.scan([valid_svg]) }.not_to raise_error
    end
  end

  describe "NullProgress" do
    it "responds to #call without error" do
      progress = described_class::NullProgress.new
      expect { progress.call(0, 1, double_report) }.not_to raise_error
    end
  end

  describe "DEFAULT_PROFILE" do
    it "is :metanorma" do
      expect(described_class::DEFAULT_PROFILE).to eq(:metanorma)
    end
  end

  def double_report
    Struct.new(:file_path, :error_count, :valid?).new("x", 0, true)
  end
end
