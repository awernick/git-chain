# frozen_string_literal: true
require "open3"
require "json"

module GitChain
  module Forge
    class Github < Base
      def cli_available?
        command_available?("gh")
      end

      def pr_for_branch(branch_name)
        fields = "number,state,isDraft,reviewDecision"
        out, _, stat = Open3.capture3(
          "gh", "pr", "list",
          "--head", branch_name,
          "--state", "all",
          "--json", fields,
          "--limit", "1"
        )
        return nil unless stat.success?

        prs = JSON.parse(out)
        return nil if prs.empty?

        normalize(prs.first)
      rescue JSON::ParserError, Errno::ENOENT
        nil
      end

      private

      # gh returns state as OPEN/MERGED/CLOSED, which matches our normalized format.
      def normalize(pr)
        {
          number: pr["number"],
          state: pr["state"],
          is_draft: pr["isDraft"],
          review_decision: pr["reviewDecision"],
        }
      end
    end
  end
end
