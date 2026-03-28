# frozen_string_literal: true

module GitChain
  module Forge
    class Base
      # Returns true if the forge CLI tool is installed and runnable.
      def cli_available?
        raise NotImplementedError
      end

      # Look up a PR/MR for the given branch.
      # Returns a hash with normalized keys, or nil if none found:
      #   { number:, state:, is_draft:, review_decision: }
      #
      # state is normalized to: "OPEN", "MERGED", "CLOSED"
      # review_decision is normalized to: "APPROVED", "CHANGES_REQUESTED",
      #   "REVIEW_REQUIRED", or nil
      def pr_for_branch(_branch_name)
        raise NotImplementedError
      end

      private

      def command_available?(cmd)
        _, _, stat = Open3.capture3(cmd, "--version")
        stat.success?
      rescue Errno::ENOENT
        false
      end
    end
  end
end
