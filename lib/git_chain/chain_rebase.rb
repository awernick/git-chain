# frozen_string_literal: true

module GitChain
  # Rebases the branches of a chain onto their parents, bottom-up.
  #
  # The service performs no output: it yields progress events and returns a
  # result, so each command keeps its own user-facing messages. branchPoint
  # configs are persisted only after every rebase has succeeded, leaving git's
  # conflict state and git-chain metadata consistent on failure.
  module ChainRebase
    # Raised when a rebase fails. Git's rebase state is left intact for the
    # user to resolve; no branchPoint configs have been written.
    class Failure < StandardError
      attr_reader :branch, :parent, :original

      def initialize(branch, parent, original)
        @branch = branch
        @parent = parent
        @original = original
        super("Cannot rebase #{branch} onto #{parent}.")
      end
    end

    # Raised when a rebase succeeded but the expected refs did not move
    # (e.g. a branch is checked out in another worktree). No branchPoint
    # configs have been written.
    class VerificationError < StandardError; end

    Result = Struct.new(:updated, keyword_init: true)

    class << self
      # Rebases each branch of the chain onto its parent.
      #
      # Yields events:
      #   [:up_to_date, branch_name]
      #   [:auto_forward, branch_name, parent_name]
      #   [:rebase_branch, branch_name, parent_name]
      #   [:rebase_command, git_args]
      #
      # Returns a Result with the number of updated branches. Raises Failure
      # if a rebase fails, or VerificationError if the fast path completed
      # without moving every expected ref.
      def call(chain, auto_forward: false, &block)
        segment = linear_segment(chain)
        return single_pass_rebase(segment, auto_forward, &block) if segment

        per_branch_rebase(chain, auto_forward, &block)
      end

      private

      # Returns the run of branches from the lowest stale branch to the tip
      # when they qualify for a single `git rebase --update-refs`, or nil.
      #
      # Qualifying requires:
      # - git >= 2.38 (--update-refs)
      # - no branch of the segment checked out in another worktree, and no
      #   segment branch other than the tip checked out here: git snapshots
      #   worktree state when the rebase starts and silently skips those refs
      # - no branch outside the segment pointing into the replayed range:
      #   --update-refs force-updates every branch pointing at a replayed
      #   commit, including branches that are not part of the chain
      # - adjacent pairs inside the segment to be nested: each parent's tip
      #   is an ancestor of its child. The pair between the segment's parent
      #   and its first branch is the relationship being rebased and is
      #   expected to be non-nested. Without nesting, side-branch commits are
      #   not on the replayed path and their refs would be left behind.
      def linear_segment(chain)
        return unless Git.supports_update_refs?

        branches = chain.branches[1..-1]
        start = branches.index { |branch| Git.rev_parse(branch.parent_branch) != branch.branch_point }
        return if start.nil?

        segment = branches[start..-1]

        return unless segment_movable?(segment)
        return if foreign_refs_in_range?(segment)

        segment.each_cons(2) do |parent, child|
          return nil unless Git.ancestor?(ancestor: parent.name, rev: child.name)
        end

        segment
      end

      def segment_movable?(segment)
        other_worktrees = Git.other_worktree_branches
        current = Git.current_branch
        tip = segment.last.name

        segment.all? do |branch|
          checked_out_here = current == branch.name
          checked_out_elsewhere = other_worktrees.include?("refs/heads/#{branch.name}")
          !checked_out_elsewhere && !(checked_out_here && branch.name != tip)
        end
      end

      def foreign_refs_in_range?(segment)
        range = Git.exec("rev-list", "#{segment.first.branch_point}..#{segment.last.name}").split("\n")
        return false if range.empty?

        segment_refs = segment.map { |branch| "refs/heads/#{branch.name}" }

        Git.branch_refs.any? do |ref, sha|
          !segment_refs.include?(ref) && range.include?(sha)
        end
      end

      def single_pass_rebase(segment, auto_forward, &block)
        lowest = segment.first
        parent_sha = Git.rev_parse(lowest.parent_branch)

        branch_point = lowest.branch_point
        if auto_forward && forwardable_branch_point?(lowest)
          branch_point = parent_sha
          yield(:auto_forward, lowest.name, lowest.parent_branch) if block
        end

        segment.each do |branch|
          yield(:rebase_branch, branch.name, branch.parent_branch) if block
        end

        args = ["rebase", "--keep-empty", "--update-refs", "--onto", lowest.parent_branch, branch_point, segment.last.name]
        yield(:rebase_command, args) if block

        begin
          Git.exec(*args)
        rescue GitChain::Git::Failure => e
          raise(Failure.new(lowest.name, lowest.parent_branch, e))
        end

        verify_segment(segment)

        segment.each do |branch|
          Git.set_config("branch.#{branch.name}.branchPoint", Git.rev_parse(branch.parent_branch), scope: :local)
        end

        Result.new(updated: segment.size)
      end

      def verify_segment(segment)
        segment.each do |branch|
          next if Git.ancestor?(ancestor: branch.parent_branch, rev: branch.name)

          raise(VerificationError, "Branch #{branch.name} was not moved by the rebase. " \
            "It may be checked out in a worktree; inspect 'git worktree list' and 'git log --graph' before retrying.")
        end
      end

      def per_branch_rebase(chain, auto_forward, &block)
        updated = 0
        pending_configs = []

        chain.branches[1..-1].each do |branch|
          parent_sha = Git.rev_parse(branch.parent_branch)

          if parent_sha == branch.branch_point
            yield(:up_to_date, branch.name) if block
            next
          end

          branch_point = branch.branch_point
          if auto_forward && forwardable_branch_point?(branch)
            branch_point = parent_sha
            yield(:auto_forward, branch.name, branch.parent_branch) if block
          end

          updated += 1
          yield(:rebase_branch, branch.name, branch.parent_branch) if block

          args = ["rebase", "--keep-empty", "--onto", branch.parent_branch, branch_point, branch.name]
          yield(:rebase_command, args) if block

          begin
            Git.exec(*args)
          rescue GitChain::Git::Failure => e
            raise(Failure.new(branch.name, branch.parent_branch, e))
          end

          pending_configs << [branch.name, parent_sha]
        end

        pending_configs.each do |name, parent_sha|
          Git.set_config("branch.#{name}.branchPoint", parent_sha, scope: :local)
        end

        Result.new(updated: updated)
      end

      def forwardable_branch_point?(branch)
        Git.ancestor?(ancestor: branch.parent_branch, rev: branch.name) ||
          Git.merge_base(branch.branch_point, Git.merge_base(branch.parent_branch, branch.name)) == branch.branch_point
      end
    end
  end
end
