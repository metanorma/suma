# frozen_string_literal: true

require "leptris"

module Suma
  module Delivery
    # Diagnostic-row census over metanorma .err.html error reports
    # (metanorma/suma#203): rows grouped by CATEGORY and RULE.
    #
    # A gate keyed on a literal code string breaks when the codes migrate
    # (iso-10303#859: the part2 gate greps STANDOC_38 in document.err.html
    # while metanorma-iso 3.5.14 re-emitted those rows as ISO_56, so the
    # gate reads 0 over 476 live rows). Codes migrate; the stable identity
    # of a diagnostic row is category + rule, so the census keys on both.
    #
    # The err.html writer is Metanorma::Utils::Log#write: one
    # `<h2 id="...">Category</h2>` per category, each followed by a table
    # whose data rows are six cells - Line, ID, Error (the rule code,
    # e.g. STANDOC_27 or ISO_56), Message, Context, Severity.
    class Diagnostics
      # The Error cell's position within a data row.
      RULE_CELL_INDEX = 2

      class << self
        # Parse one err.html given as a file path or an HTML string.
        #
        # @return [Counts] rows grouped by category, then rule
        def count(path_or_html)
          html = if File.file?(path_or_html)
                   File.read(path_or_html)
                 else
                   path_or_html
                 end
          new(html).counts
        end

        # The census of every err.html under a rendered site, summed:
        # the site-level figure an expectations gate asserts against.
        def count_site(site_dir)
          Dir.glob(File.join(site_dir, "**", "*.err.html"))
            .reduce(Counts.new) { |sum, path| sum.merge(count(path)) }
        end
      end

      def initialize(html)
        @doc = Leptris::XML.parse_html(html)
      end

      # Every data row of every category table, keyed by its h2 heading
      # (the log category) and Error cell (the rule code).
      def counts
        Counts.new(tally)
      end

      private

      # Per category, per rule, the number of data rows.
      def tally
        rows = Hash.new { |hash, category| hash[category] = Hash.new(0) }
        @doc.css("h2").each do |heading|
          rules_of(heading).each do |rule|
            rows[heading.text.strip][rule] += 1
          end
        end
        rows
      end

      # The rule code of every data row in the heading's table.
      def rules_of(heading)
        table = heading.xpath("following-sibling::table[1]").first
        return [] unless table

        table.css("tr").filter_map { |row| rule_of(row) }
      end

      # The Error cell of a row: the third of Line/ID/Error/Message/
      # Context/Severity (the ID cell renders as a `th`).
      def rule_of(row)
        rule = row.xpath("td|th")[RULE_CELL_INDEX]&.text&.strip
        rule.nil? || rule.empty? ? nil : rule
      end

      # The per-category, per-rule census of one or more err.html
      # documents: immutable value object over
      # { "Style" => { "STANDOC_48" => 15 } }, enumerable over
      # (category, rule, count) triples.
      class Counts
        include Enumerable

        def initialize(categories = {})
          @categories = categories
            .transform_values { |rules| rules.transform_values(&:to_i).freeze }
            .freeze
        end

        # The raw census hash: category => (rule => row count). Frozen.
        def to_h
          @categories
        end

        def each
          return enum_for(__method__) unless block_given?

          @categories.each do |category, rules|
            rules.each { |rule, count| yield category, rule, count }
          end
          self
        end

        # Rows counted for one rule; an unreported rule counts zero.
        def rule_count(category, rule)
          @categories.dig(category, rule) || 0
        end

        # Every row counted for one category.
        def total(category)
          @categories.fetch(category, {}).values.sum
        end

        # Rows counted overall.
        def rows
          @categories.values.sum { |rules| rules.values.sum }
        end

        # The union census: counts of both sides summed.
        def merge(other)
          other = self.class.new({}) unless other.is_a?(self.class)
          summed = other.to_h.merge(to_h) do |_category, theirs, ours|
            theirs.merge(ours) { |_rule, a, b| a + b }
          end
          self.class.new(summed)
        end
      end
    end
  end
end
