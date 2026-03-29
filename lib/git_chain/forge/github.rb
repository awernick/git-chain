# frozen_string_literal: true

require "open3"
require "json"

module GitChain
  module Forge
    class Github < Base
      def pr_for_branch(branch_name)
        fields = "number,state,isDraft,reviewDecision,url"
        out, _, stat = Open3.capture3(
          cli_command,
          "pr",
          "list",
          "--head",
          branch_name,
          "--state",
          "all",
          "--json",
          fields,
          "--limit",
          "1",
        )
        return unless stat.success?

        prs = JSON.parse(out)
        return if prs.empty?

        normalize(prs.first)
      rescue JSON::ParserError, Errno::ENOENT
        nil
      end

      private

      def default_cli_command
        "gh"
      end

      # gh returns state as OPEN/MERGED/CLOSED, which matches our normalized format.
      def normalize(pr)
        {
          number: pr["number"],
          state: pr["state"],
          is_draft: pr["isDraft"],
          review_decision: pr["reviewDecision"],
          url: pr["url"],
        }
      end
    end
  end
end
