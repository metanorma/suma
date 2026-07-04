# frozen_string_literal: true

module Suma
  # Reformats EXPRESS source into suma's canonical form: comment blocks
  # (the +(*"...\n*)+ remarks that EXPRESS uses for documentation) are
  # extracted from their inline positions and appended to the end of
  # the file, and excess blank lines are collapsed.
  #
  # Pure content transformation — no I/O, no Thor, no filesystem. The
  # CLI adapter handles reading from and writing to disk.
  #
  # The transform is idempotent: reformatting an already-reformatted
  # document returns +changed?: false+.
  module ExpressReformatter
    Result = Struct.new(:content, :changed?, keyword_init: true) do
      def content_or_nil
        changed? ? content : nil
      end
    end

    COMMENT_PATTERN = /\(\*"(.*?)\n\*\)/m
    BLANK_RUN_PATTERN = /(\n\n+)/
    NEWLINE_RUN_PATTERN = /(\n+)/

    module_function

    def call(content)
      comments = content.scan(COMMENT_PATTERN).map(&:first)
      return Result.new(content: content, changed?: false) if comments.empty?

      without_comments = content.gsub(COMMENT_PATTERN, "")
      new_comments = comments.map { |c| "(*\"#{c}\n*)" }.join("\n\n")
      # Assemble first, then collapse blank-line runs — so the seam
      # between body and appended comments is normalised along with
      # everything else. Doing it before assembly leaves a 3+ newline
      # boundary that breaks idempotence on the second pass.
      new_content = "#{without_comments}\n\n#{new_comments}\n"
      new_content = new_content.gsub(BLANK_RUN_PATTERN, "\n\n")

      changed = normalised_compare(content, new_content) != 0
      Result.new(content: new_content, changed?: changed)
    end

    def normalised_compare(left, right)
      left.gsub(NEWLINE_RUN_PATTERN, "\n") <=> right.gsub(NEWLINE_RUN_PATTERN, "\n")
    end

    private_class_method :normalised_compare
  end
end
