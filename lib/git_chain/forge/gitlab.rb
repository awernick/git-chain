# frozen_string_literal: true

require "open3"
require "json"

module GitChain
  module Forge
    class Gitlab < Base
      def pr_for_branch(branch_name)
        out, _, stat = Open3.capture3(
          cli_command,
          "mr",
          "list",
          "--source-branch",
          branch_name,
          "--all",
          "-F",
          "json",
        )
        return unless stat.success?

        mrs = JSON.parse(out)
        return if mrs.empty?

        normalize(mrs.first)
      rescue JSON::ParserError, Errno::ENOENT
        nil
      end

      private

      def default_cli_command
        "glab"
      end

      # glab returns state as "opened"/"merged"/"closed".
      # Normalize to our uppercase format: OPEN/MERGED/CLOSED.
      def normalize(mr)
        {
          number: mr["iid"],
          state: normalize_state(mr["state"]),
          is_draft: mr.fetch("draft", false),
          review_decision: nil, # GitLab MRs don't have a direct equivalent
          url: mr["web_url"],
        }
      end

      def normalize_state(state)
        case state
        when "opened" then "OPEN"
        when "merged" then "MERGED"
        when "closed" then "CLOSED"
        else state.to_s.upcase
        end
      end
    end
  end
end
