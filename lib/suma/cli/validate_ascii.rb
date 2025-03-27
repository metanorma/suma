# frozen_string_literal: true

require "thor"
require "yaml"
require "terminal-table"
require "plurimath"
require "set" # For using Set in unique_character_count
require_relative "../thor_ext"

module Suma
  module Cli
    # Represents a non-ASCII character with its details and replacement
    class NonAsciiCharacter
      attr_reader :char, :hex, :utf8, :is_math, :replacement,
                  :replacement_type, :occurrences

      def initialize(char, hex, utf8, is_math, replacement, replacement_type)
        @char = char
        @hex = hex
        @utf8 = utf8
        @is_math = is_math
        @replacement = replacement
        @replacement_type = replacement_type
        @occurrences = []
      end

      def add_occurrence(line_number, column, line)
        @occurrences << {
          line_number: line_number,
          column: column,
          line: line,
        }
      end

      def replacement_text
        @is_math ? "AsciiMath: #{@replacement}" : "ISO 10303-11: #{@replacement}"
      end

      def occurrence_count
        @occurrences.size
      end

      def to_h
        {
          character: @char,
          hex: @hex,
          utf8: @utf8,
          is_math: @is_math,
          replacement_type: @replacement_type,
          replacement: @replacement,
          occurrence_count: occurrence_count,
          occurrences: @occurrences,
        }
      end
    end

    # Represents all non-ASCII characters in a file
    class FileViolations
      attr_reader :path, :filename, :directory, :violations, :unique_characters

      def initialize(file_path)
        @path = file_path
        @filename = File.basename(file_path)
        @directory = File.dirname(file_path)
        @characters = {}  # Map of characters to NonAsciiCharacter objects
        @violations = []  # List of violations (line, column, etc.)
      end

      def add_violation(line_number, column, match, char_details, line)
        violation = {
          line_number: line_number,
          column: column,
          match: match,
          char_details: char_details,
          line: line,
        }

        @violations << violation

        # Register each character
        char_details.each do |detail|
          char = detail[:char]
          unless @characters[char]
            @characters[char] = NonAsciiCharacter.new(
              char,
              detail[:hex],
              detail[:utf8],
              detail[:is_math],
              detail[:replacement],
              detail[:replacement_type],
            )
          end

          @characters[char].add_occurrence(line_number, column, line)
        end
      end

      def violation_count
        @violations.size
      end

      def unique_characters
        @characters.values
      end

      def display_path
        "#{File.basename(@directory)}/#{@filename}"
      end

      def full_path
        File.expand_path(@path)
      end

      def to_h
        {
          file: display_path,
          count: violation_count,
          non_ascii_characters: unique_characters.map(&:to_h),
        }
      end
    end

    # Collection of all violations across multiple files
    class NonAsciiViolationCollection
      attr_reader :file_violations, :total_files

      def initialize
        @file_violations = {} # Map of file paths to FileViolations objects
        @total_files = 0
        @unicode_to_asciimath = nil
      end

      def process_file(file)
        @total_files += 1

        # Initialize the mapping once
        @unicode_to_asciimath ||= build_unicode_to_asciimath_map

        file_violations = process_file_violations(file)
        return if file_violations.violations.empty?

        @file_violations[file] = file_violations
      end

      def files_with_violations
        @file_violations.size
      end

      def total_violations
        @file_violations.values.sum(&:violation_count)
      end

      def unique_character_count
        # Get total unique characters across all files
        all_chars = Set.new
        @file_violations.each_value do |file_violation|
          file_violation.unique_characters.each do |char|
            all_chars.add(char.char)
          end
        end
        all_chars.size
      end

      def total_occurrence_count
        # Sum all occurrences of all characters across all files
        @file_violations.values.sum do |file_violation|
          file_violation.unique_characters.sum(&:occurrence_count)
        end
      end

      def to_yaml_data
        {
          summary: {
            total_files: @total_files,
            files_with_violations: files_with_violations,
            total_violations: total_violations,
            total_unique_characters: unique_character_count,
            total_occurrences: total_occurrence_count,
          },
          violations: @file_violations.transform_keys do |k|
            File.expand_path(k)
          end.transform_values(&:to_h),
        }
      end

      def print_text_output
        return if @file_violations.empty?

        # Print each file's violations
        @file_violations.each_value do |file_violation|
          puts "\n#{file_violation.display_path}:"

          file_violation.violations.each do |v|
            puts "  Line #{v[:line_number]}, Column #{v[:column]}:"
            puts "    #{v[:line]}"
            puts "    #{' ' * v[:column]}#{'^' * v[:match].length} Non-ASCII sequence"

            v[:char_details].each do |cd|
              character = file_violation.unique_characters.find do |c|
                c.char == cd[:char]
              end
              next unless character

              puts "      \"#{cd[:char]}\" - Hex: #{cd[:hex]}, UTF-8 bytes: #{cd[:utf8]}"
              puts "      Replacement: #{character.replacement_text}"
            end
            puts ""
          end

          puts "  Found #{file_violation.violation_count} non-ASCII sequence(s) in #{file_violation.filename}\n"
        end

        # Print summary
        puts "\nSummary:"
        puts "  Scanned #{@total_files} EXPRESS file(s)"
        puts "  Found #{total_violations} non-ASCII sequence(s) in #{files_with_violations} file(s)"
      end

      def print_table_output
        return if @file_violations.empty?

        table = ::Terminal::Table.new(
          title: "Non-ASCII Characters Summary",
          headings: ["File", "Symbol", "Replacement", "Occurrences"],
        )

        total_occurrences = 0

        @file_violations.each_value do |file_violation|
          file_violation.unique_characters.each do |character|
            occurrence_count = character.occurrence_count
            total_occurrences += occurrence_count

            table.add_row [
              file_violation.display_path,
              "\"#{character.char}\" (#{character.hex})",
              character.replacement_text,
              occurrence_count,
            ]
          end
        end

        # Add a separator and total row
        table.add_separator
        table.add_row [
          "TOTAL",
          "#{unique_character_count} unique",
          "",
          total_occurrences,
        ]

        puts "\n#{table}\n"
      end

      private

      def process_file_violations(file)
        file_violations = FileViolations.new(file)

        # Process file line by line
        File.readlines(file,
                       encoding: "UTF-8").each_with_index do |line, line_idx|
          line_number = line_idx + 1

          # Skip if line only contains ASCII
          next unless /[^\x00-\x7F]/.match?(line)

          # Find all non-ASCII sequences
          line.chomp.scan(/([^\x00-\x7F]+)/) do |match|
            match = match[0]
            column = line.index(match)

            # Process each character in the sequence
            char_details = match.chars.map do |c|
              process_non_ascii_char(c)
            end.compact

            # Skip if no non-ASCII characters found
            next if char_details.empty?

            file_violations.add_violation(line_number, column, match,
                                          char_details, line.chomp)
          end
        end

        file_violations
      end

      def process_non_ascii_char(char)
        # Skip ASCII characters
        return nil if char.ord <= 0x7F

        code_point = char.ord
        hex = "0x#{code_point.to_s(16)}"
        utf8 = code_point.chr(Encoding::UTF_8).bytes.map do |b|
          "0x#{b.to_s(16)}"
        end.join(" ")

        # Check if it's a math symbol
        if asciimath = @unicode_to_asciimath[char]
          return {
            char: char,
            hex: hex,
            utf8: utf8,
            is_math: true,
            replacement: asciimath,
            replacement_type: "asciimath",
          }
        end

        # Not a math symbol, use ISO encoding
        {
          char: char,
          hex: hex,
          utf8: utf8,
          is_math: false,
          replacement: encode_iso_10303_11(char),
          replacement_type: "iso-10303-11",
        }
      end

      def encode_iso_10303_11(char)
        code_point = char.ord

        # Format the encoded value with double quotes
        if code_point < 0x10000
          "\"#{sprintf('%08X', code_point)}\"" # e.g., "00000041" for 'A'
        else
          # For higher code points, use all four octets
          group = (code_point >> 24) & 0xFF
          plane = (code_point >> 16) & 0xFF
          row = (code_point >> 8) & 0xFF
          cell = code_point & 0xFF

          "\"#{sprintf('%02X%02X%02X%02X', group, plane, row, cell)}\""
        end
      end

      def build_unicode_to_asciimath_map
        # Start with a pre-defined mapping of common math symbols
        unicode_to_asciimath = {
          # Greek letters
          "α" => "alpha",
          "β" => "beta",
          "γ" => "gamma",
          "Γ" => "Gamma",
          "δ" => "delta",
          "Δ" => "Delta",
          "ε" => "epsilon",
          "ζ" => "zeta",
          "η" => "eta",
          "θ" => "theta",
          "Θ" => "Theta",
          "ι" => "iota",
          "κ" => "kappa",
          "λ" => "lambda",
          "Λ" => "Lambda",
          "μ" => "mu",
          "ν" => "nu",
          "ξ" => "xi",
          "Ξ" => "Xi",
          "π" => "pi",
          "Π" => "Pi",
          "ρ" => "rho",
          "σ" => "sigma",
          "Σ" => "Sigma",
          "τ" => "tau",
          "υ" => "upsilon",
          "φ" => "phi",
          "Φ" => "Phi",
          "χ" => "chi",
          "ψ" => "psi",
          "Ψ" => "Psi",
          "ω" => "omega",
          "Ω" => "Omega",

          # Math operators
          "×" => "xx",
          "÷" => "div",
          "±" => "pm",
          "∓" => "mp",
          "∞" => "oo",
          "≤" => "le",
          "≥" => "ge",
          "≠" => "ne",
          "≈" => "~~",
          "≅" => "cong",
          "≡" => "equiv",
          "∈" => "in",
          "∉" => "notin",
          "⊂" => "subset",
          "⊃" => "supset",
          "∩" => "cap",
          "∪" => "cup",
          "∧" => "and",
          "∨" => "or",
          "¬" => "neg",
          "∀" => "forall",
          "∃" => "exists",
          "∄" => "nexists",
          "∇" => "grad",
          "∂" => "del",
          "∑" => "sum",
          "∏" => "prod",
          "∫" => "int",
          "∮" => "oint",
          "√" => "sqrt",
          "⊥" => "perp",
          "‖" => "norm",
          "→" => "rarr",
          "←" => "larr",
          "↔" => "harr",
          "⇒" => "rArr",
          "⇐" => "lArr",
          "⇔" => "hArr",
        }

        # Augment with symbols from Plurimath
        begin
          # Get all symbols supported by AsciiMath
          Plurimath::Utility.symbols_files.each do |symbol_class|
            symbol = symbol_class.new

            # Get the Unicode and AsciiMath representations
            unicodes = symbol.to_unicodemath
            asciimaths = symbol.to_asciimath

            # Skip if either representation is missing
            next unless unicodes.is_a?(Array) && asciimaths.is_a?(Array)
            # Skip if empty arrays
            next if unicodes.empty? || asciimaths.empty?

            unicodes.each_with_index do |unicode, index|
              # Skip if we're beyond available AsciiMath representations
              next if index >= asciimaths.length
              # Skip empty string values
              next if unicode.to_s.empty?

              # Map each character to its AsciiMath equivalent
              unicode.to_s.chars.each do |char|
                # Only add if not already in our mapping
                unicode_to_asciimath[char] ||= asciimaths[index]
              end
            end
          rescue StandardError => e
            # Skip this symbol class if there's an error
            puts "Warning: Error processing symbol class #{symbol_class}: #{e.message}" if $DEBUG
          end
        rescue StandardError => e
          # Continue even if Plurimath integration fails
          puts "Warning: Error loading Plurimath symbols: #{e.message}" if $DEBUG
        end

        unicode_to_asciimath
      end
    end

    # ValidateAscii command for checking EXPRESS files for non-ASCII characters
    class ValidateAscii < Thor
      desc "validate-ascii EXPRESS_FILE_PATH",
           "Validate EXPRESS files for ASCII-only content"
      option :recursive, type: :boolean, default: false, aliases: "-r",
                         desc: "Validate EXPRESS files under the specified " \
                               "path recursively"
      option :yaml, type: :boolean, default: false, aliases: "-y",
                    desc: "Output results in YAML format"

      def validate_ascii(express_file_path) # rubocop:disable Metrics/AbcSize
        if File.file?(express_file_path)
          unless File.exist?(express_file_path)
            raise Errno::ENOENT, "Specified EXPRESS file " \
                                 "`#{express_file_path}` not found."
          end

          if File.extname(express_file_path) != ".exp"
            raise ArgumentError, "Specified file `#{express_file_path}` is " \
                                 "not an EXPRESS file."
          end

          exp_files = [express_file_path]
        elsif options[:recursive]
          # Support the relative path with glob pattern
          base_path = File.expand_path(express_file_path)
          exp_files = Dir.glob("#{base_path}/**/*.exp")
        else
          # Non-recursive option
          base_path = File.expand_path(express_file_path)
          exp_files = Dir.glob("#{base_path}/*.exp")
        end

        if exp_files.empty?
          raise Errno::ENOENT, "No EXPRESS files found in " \
                               "`#{express_file_path}`."
        end

        run(exp_files)
      end

      private

      def run(exp_files)
        # Process all files and collect violations
        collection = NonAsciiViolationCollection.new

        exp_files.each do |exp_file|
          collection.process_file(exp_file)
        end

        # Output results based on format
        if options[:yaml]
          puts collection.to_yaml_data.to_yaml
        else
          collection.print_text_output
          collection.print_table_output if collection.files_with_violations.positive?
        end
      end
    end
  end
end
