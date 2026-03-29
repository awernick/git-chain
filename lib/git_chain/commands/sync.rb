# frozen_string_literal: true

require "optparse"

module GitChain
  module Commands
    class Sync < Command
      include Options::ChainName

      def description
        "Sync chain after branches have been merged"
      end

      def configure_option_parser(opts, options)
        super

        opts.on("-n", "--dry-run", "Show what would happen without making changes") do
          options[:dry_run] = true
        end
      end

      def run(options)
        if Git.rebase_in_progress?
          raise(Abort, "A rebase is in progress. Please finish the rebase first.")
        end

        chain = current_chain(options)
        merged = detect_merged_branches(chain)

        if merged.empty?
          puts_info("No merged branches detected in chain {{info:#{chain.name}}}.")
          return
        end

        merged.each do |name, pr|
          puts_info("Detected merged branch: {{info:#{name}}} (##{pr[:number]})")
        end

        remaining = chain.branch_names.reject { |b| merged.key?(b) }

        if options[:dry_run]
          merged.each_key do |name|
            puts_info("Would remove {{info:#{name}}} from chain {{info:#{chain.name}}}")
          end

          if remaining.size > 1
            remaining[1..-1].each_with_index do |name, i|
              parent = remaining[i]
              puts_info("Would rebase {{info:#{name}}} onto {{info:#{parent}}}")
            end
          end

          puts_info("Remaining chain: #{remaining.join(" -> ")}")
          return
        end

        original_branch = Git.current_branch

        if remaining.size <= 1
          remove_branches_from_config(merged.keys)
          Git.exec("checkout", remaining.first) if original_branch != remaining.first
          puts_success("All branches in chain {{info:#{chain.name}}} have been merged.")
          return
        end

        reconfigure_chain(chain, remaining, merged.keys)
        rebase_chain(chain.name)

        target = remaining.include?(original_branch) ? original_branch : remaining.last
        Git.exec("checkout", target)

        puts_success("Done. Remaining chain: #{remaining.join(" -> ")}")
      end

      private

      def detect_merged_branches(chain)
        forge = Forge.detect!(remote_url: chain.remote_url)

        merged = {}
        chain.branches[1..-1].each do |branch|
          pr = forge.pr_for_branch(branch.name)
          merged[branch.name] = pr if pr && pr[:state] == "MERGED"
        end
        merged
      end

      def reconfigure_chain(_chain, remaining, merged_names)
        # Compute all new config values before writing any changes,
        # so a nil merge-base aborts without leaving partial updates.
        updates = []
        remaining.each_with_index do |name, i|
          next if i == 0

          parent_name = remaining[i - 1]
          branch_point = Git.merge_base(parent_name, name)

          unless branch_point
            raise(Abort, "Branch {{info:#{name}}} and {{info:#{parent_name}}} have no common ancestor. " \
              "Cannot reconfigure chain.")
          end

          updates << { name: name, parent: parent_name, branch_point: branch_point }
        end

        updates.each do |update|
          Git.set_config("branch.#{update[:name]}.parentBranch", update[:parent], scope: :local)
          Git.set_config("branch.#{update[:name]}.branchPoint", update[:branch_point], scope: :local)
        end

        remove_branches_from_config(merged_names)
      end

      def remove_branches_from_config(branch_names)
        branch_names.each do |name|
          Git.set_config("branch.#{name}.chain", nil, scope: :local)
          Git.set_config("branch.#{name}.parentBranch", nil, scope: :local)
          Git.set_config("branch.#{name}.branchPoint", nil, scope: :local)
        end
      end

      def rebase_chain(chain_name)
        chain = Models::Chain.from_config(chain_name)

        chain.branches[1..-1].each do |branch|
          parent_sha = Git.rev_parse(branch.parent_branch)

          if parent_sha == branch.branch_point
            puts_debug("Branch {{info:#{branch.name}}} is already up-to-date.")
            next
          end

          args = ["rebase", "--keep-empty", "--onto", branch.parent_branch, branch.branch_point, branch.name]
          puts_info("Rebasing {{info:#{branch.name}}} onto {{info:#{branch.parent_branch}}}")
          Git.exec(*args)
          Git.set_config("branch.#{branch.name}.branchPoint", parent_sha, scope: :local)
        rescue Git::Failure => e
          puts_warning(e.message)
          puts_error("Cannot rebase {{info:#{branch.name}}} onto {{info:#{branch.parent_branch}}}.")
          puts_error("The chain has been reconfigured. Resolve the conflict, then run:")
          puts_error("  {{command:git rebase --continue}} followed by {{command:git chain rebase}}")
          raise(AbortSilent)
        end
      end
    end
  end
end
