# frozen_string_literal: true

module Suma
  module Eengine
    # Base error class for eengine-related errors
    class EengineError < StandardError; end

    # Raised when eengine binary is not found in PATH
    class EengineNotFoundError < EengineError
      def initialize
        super("eengine not found in PATH. Install eengine:\n  " \
              "macOS: https://github.com/expresslang/homebrew-eengine\n  " \
              "Linux: https://github.com/expresslang/eengine-releases")
      end
    end

    # Raised when eengine comparison fails
    class ComparisonError < EengineError
      attr_reader :stderr

      def initialize(message, stderr = nil)
        super(message)
        @stderr = stderr
      end
    end
  end
end
