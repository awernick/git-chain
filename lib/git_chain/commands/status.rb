# frozen_string_literal: true
require "optparse"

module GitChain
  module Commands
    class Status < Command
      include Options::ChainName

      def description
        "Show status of the current chain"
      end

      def configure_option_parser(opts, options)
        super

        opts.on("--no-pr", "Skip PR status lookup") do
          options[:no_pr] = true
        end
      end

      def run(options)
        chain = current_chain(options)
        current_branch = Git.current_branch
        branches = chain.branches
        pr_info = options[:no_pr] ? {} : fetch_pr_info(chain)

        puts("{{bold:#{chain.name}}}")

        branches.each_with_index do |branch, index|
          is_last = index == branches.size - 1
          is_current = branch.name == current_branch
          is_base = index == 0

          connector = if is_base
            ""
          elsif is_last
            "\u2514\u2500\u2500 "
          else
            "\u251C\u2500\u2500 "
          end

          indent = is_base ? "  " : "  "

          name_str = if is_current
            "{{yellow:#{branch.name}}} {{yellow:(HEAD)}}"
          else
            "{{cyan:#{branch.name}}}"
          end

          details = build_details(branch, is_base, pr_info)
          puts("#{indent}#{connector}#{name_str}#{details}")
        end
      end

      private

      def build_details(branch, is_base, pr_info)
        parts = []

        unless is_base
          counts = Git.ahead_behind(branch.name, branch.parent_branch)
          if counts
            ahead = counts[:ahead]
            behind = counts[:behind]
            if ahead > 0 || behind > 0
              count_parts = []
              count_parts << "#{ahead} ahead" if ahead > 0
              count_parts << "#{behind} behind" if behind > 0
              parts << count_parts.join(", ")
            end
          end
        end

        pr = pr_info[branch.name]
        if pr
          state = pr[:state]
          state_str = case state
          when "MERGED"
            "{{green:merged}}"
          when "CLOSED"
            "{{red:closed}}"
          when "OPEN"
            pr[:is_draft] ? "{{cyan:draft}}" : "{{green:open}}"
          else
            state.downcase
          end

          parts << "##{pr[:number]} #{state_str}"

          if pr[:review_decision] && state == "OPEN"
            review_str = case pr[:review_decision]
            when "APPROVED"
              "{{green:approved}}"
            when "CHANGES_REQUESTED"
              "{{red:changes requested}}"
            when "REVIEW_REQUIRED"
              "review required"
            end
            parts << review_str if review_str
          end
        end

        return "" if parts.empty?
        " (#{parts.join(", ")})"
      end

      def fetch_pr_info(chain)
        forge = Forge.detect(remote_url: chain.remote_url)
        return {} unless forge&.cli_available?

        info = {}
        chain.branches.each do |branch|
          next if branch.parent_branch.nil? # skip base branch
          pr = forge.pr_for_branch(branch.name)
          info[branch.name] = pr if pr
        end
        info
      end
    end
  end
end
