# frozen_string_literal: true

require "optparse"

module GitChain
  module Commands
    class Adopt < Command
      include Options::ChainName

      def banner_options
        "[branch]"
      end

      def description
        "Adopt an existing branch into the chain"
      end

      def configure_option_parser(opts, options)
        super

        opts.on("--after=BRANCH", "Insert the adopted branch after BRANCH in the chain") do |name|
          options[:after] = name
        end

        opts.on("--rebase", "Rebase the adopted branch onto its new parent") do
          options[:rebase] = true
        end

        opts.on("--force", "Move a branch that is already in another chain") do
          options[:force] = true
        end
      end

      def post_process_options!(options)
        # Track whether chain_name was explicitly provided via -c before
        # ChainName#post_process_options! auto-detects from current branch
        options[:explicit_chain_name] = options[:chain_name]

        super

        raise(ArgError, "Expected 0 or 1 arguments") if options[:args].size > 1
      end

      def run(options)
        # == Phase 1: Validation (read-only, no mutations) ==

        if Git.rebase_in_progress?
          raise(Abort, "A rebase is in progress. Please finish the rebase first.")
        end

        # 1. Resolve branch name
        branch_name = options[:args][0]
        unless branch_name
          branch_name = Git.current_branch
          raise(Abort, "You are not currently on any branch") unless branch_name
        end

        # 2. Validate branch exists
        unless Git.branches.include?(branch_name)
          raise(Abort, "Branch '#{branch_name}' does not exist.")
        end

        # 3. Validate --after branch exists
        if options[:after]
          unless Git.branches.include?(options[:after])
            raise(Abort, "#{options[:after]} is not a branch")
          end
        end

        # 4. Resolve target chain
        # When --after is used, only pass explicitly-provided chain name (from -c flag),
        # not the auto-detected one from current branch. The --after branch determines
        # the chain unless -c is explicitly given.
        chain = if options[:after]
          find_chain_for_branch(options[:after], options[:explicit_chain_name])
        else
          current_chain(options)
        end

        # 5. Check if branch is already in a chain
        existing_branch = Models::Branch.from_config(branch_name)
        old_chain = nil
        old_chain_name = existing_branch.chain_name

        # Also check if the branch is a base of any chain (base branches don't
        # have chain config set, but are referenced as parentBranch by others)
        if old_chain_name.nil?
          base_of_chain = find_chain_where_base(branch_name)
          if base_of_chain
            raise(
              Abort,
              "Cannot adopt '#{branch_name}' because it is the base branch of chain " \
                "'#{base_of_chain.name}'. Remove it from the chain first with 'git chain setup'.",
            )
          end
        end

        if old_chain_name
          if old_chain_name == chain.name
            raise(Abort, "Branch '#{branch_name}' is already in chain '#{chain.name}'.")
          end

          unless options[:force]
            raise(
              Abort,
              "Branch '#{branch_name}' is already in chain '#{old_chain_name}'. Use --force to move it.",
            )
          end

          # Load old chain and verify branch is not the base
          old_chain = Models::Chain.from_config(old_chain_name)
          if old_chain.branch_names.first == branch_name
            raise(
              Abort,
              "Cannot adopt '#{branch_name}' because it is the base branch of chain " \
                "'#{old_chain.name}'. Remove it from the chain first with 'git chain setup'.",
            )
          end
        end

        # 6. Build new branch list
        branch_names = chain.branch_names.dup
        if options[:after]
          index = branch_names.index(options[:after])
          raise(Abort, "Branch '#{options[:after]}' is not in chain '#{chain.name}'.") unless index

          branch_names.insert(index + 1, branch_name)
        else
          branch_names << branch_name
        end

        # 7. Pre-validate new chain connectivity
        if Git.merge_base(*branch_names).nil?
          raise(Abort, "Branches are not all connected")
        end

        # == Phase 2: Mutation (all validations passed) ==

        # 8. Remove from old chain if --force
        if old_chain
          remove_from_old_chain(branch_name, old_chain)
        end

        # 9. Persist new chain
        Setup.new.call(["--chain", chain.name, *branch_names])

        # 10. Optional targeted rebase
        if options[:rebase]
          perform_targeted_rebase(branch_name, branch_names)
          # Re-run Setup to recompute branchPoints for downstream branches
          # whose merge-base may have changed after the rebase
          Setup.new.call(["--chain", chain.name, *branch_names])
        end

        # 11. Success message
        updated_chain = Models::Chain.from_config(chain.name)
        puts_success("Adopted {{info:#{branch_name}}} into chain #{updated_chain.formatted}")
      end

      private

      def remove_from_old_chain(branch_name, old_chain)
        old_branch_names = old_chain.branch_names.dup
        adopted_index = old_branch_names.index(branch_name)

        # Re-parent downstream branch if adopted branch was in the middle
        if adopted_index < old_branch_names.size - 1
          downstream_name = old_branch_names[adopted_index + 1]
          upstream_name = old_branch_names[adopted_index - 1]
          merge_base_sha = Git.merge_base(upstream_name, downstream_name)

          Git.set_config("branch.#{downstream_name}.parentBranch", upstream_name, scope: :local)
          Git.set_config("branch.#{downstream_name}.branchPoint", merge_base_sha, scope: :local) if merge_base_sha
        end

        # Clear adopted branch config
        Git.set_config("branch.#{branch_name}.chain", nil, scope: :local)
        Git.set_config("branch.#{branch_name}.parentBranch", nil, scope: :local)
        Git.set_config("branch.#{branch_name}.branchPoint", nil, scope: :local)

        # Rebuild old chain without the adopted branch
        remaining = old_branch_names.reject { |b| b == branch_name }
        if remaining.size > 1
          # Has base + at least one branch, rebuild
          Setup.new.call(["--chain", old_chain.name, *remaining])
        end
        # If remaining.size <= 1, only the base is left; chain disappears naturally
      end

      def perform_targeted_rebase(branch_name, new_branch_names)
        index = new_branch_names.index(branch_name)
        parent_name = new_branch_names[index - 1]
        old_base = Git.merge_base(parent_name, branch_name)

        args = ["rebase", "--keep-empty", "--onto", parent_name, old_base, branch_name]
        puts_debug_git(*args)
        Git.exec(*args)

        parent_sha = Git.rev_parse(parent_name)
        Git.set_config("branch.#{branch_name}.branchPoint", parent_sha, scope: :local)

        # Restore checkout if needed
        if Git.current_branch != branch_name
          Git.exec("checkout", branch_name)
        end
      rescue GitChain::Git::Failure => e
        puts_warning(e.message)
        puts_error("Fix the rebase and run {{command:git chain rebase}} to continue.")
        raise(AbortSilent)
      end

      def find_chain_where_base(branch_name)
        all_chains = Git.chains
        chain_names = all_chains.values.uniq

        chain_names.each do |name|
          chain = Models::Chain.from_config(name)
          return chain if chain.branch_names.first == branch_name
        end

        nil
      end

      def find_chain_for_branch(target, explicit_chain_name = nil)
        all_chains = Git.chains
        chain_names = all_chains.values.uniq

        matching = []
        chain_names.each do |name|
          chain = Models::Chain.from_config(name)
          matching << chain if chain.branch_names.include?(target)
        end

        if explicit_chain_name
          chain = Models::Chain.from_config(explicit_chain_name)
          unless chain.branch_names.include?(target)
            raise(Abort, "Branch '#{target}' is not in chain '#{explicit_chain_name}'.")
          end

          return chain
        end

        if matching.empty?
          raise(Abort, "Branch '#{target}' is not in any chain.")
        end

        if matching.size > 1
          names = matching.map(&:name).join(", ")
          raise(Abort, "Branch '#{target}' belongs to multiple chains: #{names}. Use --chain to specify.")
        end

        matching.first
      end
    end
  end
end
