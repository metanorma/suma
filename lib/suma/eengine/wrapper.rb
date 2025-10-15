# frozen_string_literal: true

require "open3"
require_relative "errors"

module Suma
  module Eengine
    # Wrapper for eengine binary to compare EXPRESS schemas
    class Wrapper
      class << self
        # Compare two EXPRESS schemas using eengine
        #
        # @param trial_schema [String] Path to the new/trial schema
        # @param reference_schema [String] Path to the old/reference schema
        # @param options [Hash] Comparison options
        # @option options [String] :mode Comparison mode (resource/module)
        # @option options [String] :trial_stepmod Path to trial repo root
        # @option options [String] :reference_stepmod Path to reference repo root
        # @return [Hash] Result with :success, :xml_path, :has_changes, :output
        def compare(trial_schema, reference_schema, options = {})
          ensure_eengine_available!

          cmd = build_command(trial_schema, reference_schema, options)
          output, error, status = Open3.capture3(*cmd)

          unless status.success?
            error_message = error.empty? ? "Unknown eengine error" : error.strip
            raise ComparisonError.new(error_message, error)
          end

          parse_output(output, options)
        end

        # Check if eengine is available on the system
        #
        # @return [Boolean] true if eengine binary is found
        def available?
          return false if ENV["EENGINE_DISABLED"] == "true"

          eengine_path && eengine_executable?
        end

        # Get the eengine version
        #
        # @return [String, nil] Version string or nil if unavailable
        def version
          return nil unless available?

          cmd = [eengine_path, "--version"]
          output, _, status = Open3.capture3(*cmd)
          status.success? ? parse_version(output) : nil
        rescue StandardError
          nil
        end

        private

        def eengine_path
          @eengine_path ||= find_eengine_binary
        end

        def find_eengine_binary
          # Search for eengine or eengine-* in PATH
          ENV["PATH"].split(File::PATH_SEPARATOR).each do |dir|
            # First try plain eengine
            plain_path = File.join(dir, "eengine")
            return plain_path if File.exist?(plain_path) && File.executable?(plain_path)

            # Then try eengine-* pattern
            Dir.glob(File.join(dir, "eengine-*")).each do |path|
              return path if File.executable?(path)
            end
          end
          nil
        end

        def eengine_executable?
          eengine_path && File.executable?(eengine_path)
        end

        def ensure_eengine_available!
          raise EengineNotFoundError unless available?
        end

        def build_command(trial, reference, options)
          cmd = [
            eengine_path,
            "--compare",
            "-trial_schema", trial,
            "-trial_stepmod", options[:trial_stepmod] || ".",
            "-reference_schema", reference,
            "-reference_stepmod", options[:reference_stepmod] || ".",
            "-mode", options[:mode] || "resource",
            "--xml-output",
          ]

          # Add output directory if specified
          if options[:out_dir]
            cmd += ["-out-dir", options[:out_dir]]
          end

          cmd
        end

        def parse_output(output, _options)
          # Extract XML file path from output
          # eengine prints: "Writing \"path/to/file.xml\""
          xml_match = output.match(/Writing "(.+\.xml)"/)
          xml_path = xml_match ? xml_match[1] : nil

          # Expand to absolute path if found
          xml_path = File.expand_path(xml_path) if xml_path

          # Determine if changes were detected
          has_changes = detect_changes(output)

          {
            success: true,
            xml_path: xml_path,
            has_changes: has_changes,
            output: output,
          }
        end

        def detect_changes(output)
          # Check for various indicators of changes in the output
          return true if output.include?("Comparing TYPE")
          return true if output.include?("Comparing ENTITY")
          return true if output.include?("Comparing FUNCTION")
          return true if output.include?("Comparing RULE")
          return true if output.include?("Comparing PROCEDURE")

          # Check for modification indicators
          return true if output.include?("changed")
          return true if output.include?("modified")
          return true if output.include?("added")
          return true if output.include?("removed")

          false
        end

        def parse_version(output)
          # Extract version from output like "Express Engine 5.2.7"
          version_match = output.match(/Express Engine ([\d.]+)/)
          version_match ? version_match[1] : nil
        end
      end
    end
  end
end
