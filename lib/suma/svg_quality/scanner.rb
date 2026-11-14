# frozen_string_literal: true

require "svg_conform"

module Suma
  module SvgQuality
    # Deep module behind the SVG-quality seam: takes paths in, returns
    # +Report+ / +BatchReport+ out. Owns validator construction and
    # per-file result capture. Does not own file discovery, sorting,
    # filtering, or presentation — those stay in the CLI adapter.
    #
    # The progress adapter is injected: pass any object responding to
    # +#call(index, total, report)+. +NullProgress+ is the default
    # no-op; the CLI passes a lambda that writes to +$stderr+.
    class Scanner
      # The operative metanorma profile ships from metanorma-standoc by
      # path: svg_conform's bundled copy is a sample only, and the
      # "metanorma" engine name fails loudly by design (svg_conform#132).
      STANDOC_PROFILE_PATH =
        "lib/metanorma/standoc/svg_conform_profile/metanorma.yml"

      def self.default_profile
        File.join(
          Gem::Specification.find_by_name("metanorma-standoc").gem_dir,
          STANDOC_PROFILE_PATH,
        )
      end

      attr_reader :profile, :progress

      def initialize(profile: nil,
                     progress: NullProgress.new)
        @profile = profile || self.class.default_profile
        @progress = progress
      end

      def scan(paths)
        validator = build_validator
        reports = paths.each_with_index.map do |path, index|
          scan_one(validator, path, index, paths.size)
        end
        BatchReport.new(reports)
      end

      def scan_file(path)
        Report.new(path.to_s, build_validator.validate_file(path.to_s,
                                                            profile: profile))
      end

      # Default no-op progress adapter. Real progress reporters are
      # passed by the caller; this satisfies the same interface so the
      # scanner can be invoked from specs without forcing the
      # dependency.
      class NullProgress
        def call(_index, _total, _report); end
      end

      private

      def build_validator
        SvgConform::Validator.new
      end

      def scan_one(validator, path, index, total)
        result = validator.validate_file(path.to_s, profile: profile)
        report = Report.new(path.to_s, result)
        progress.call(index, total, report)
        report
      end
    end
  end
end
