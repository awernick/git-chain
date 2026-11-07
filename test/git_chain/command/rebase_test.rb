# frozen_string_literal: true

require "test_helper"

module GitChain
  module Commands
    class RebaseTest < Minitest::Test
      include RepositoryTestHelper

      def test_rebasing_a_clean_chain
        capture_io do
          with_test_repository("a-b-chain") do
            Rebase.new.call

            assert_equal(Git.rev_parse("master"), Git.merge_base("master", "a"))
            assert_equal(Git.rev_parse("a"), Git.merge_base("a", "b"))

            assert_equal(Git.rev_parse("master"), Git.get_config("branch.a.branchPoint"))
            assert_equal(Git.rev_parse("a"), Git.get_config("branch.b.branchPoint"))
          end
        end
      end

      def test_conflict
        capture_io do
          with_test_repository("a-b-conflicts") do
            assert_raises(AbortSilent) do
              Rebase.new.run(chain_name: "default")
            end

            Git.exec("add", ".")
            Git.exec("commit", "-m", "message")
            Git.exec("rebase", "--continue")

            Rebase.new.call

            assert_equal(Git.rev_parse("master"), Git.merge_base("master", "a"))
            assert_equal(Git.rev_parse("a"), Git.merge_base("a", "b"))

            assert_equal(Git.rev_parse("master"), Git.get_config("branch.a.branchPoint"))
            assert_equal(Git.rev_parse("a"), Git.get_config("branch.b.branchPoint"))
            assert_equal(Git.rev_parse("master"), Git.merge_base("master", "a"))
            assert_equal(Git.rev_parse("a"), Git.merge_base("a", "b"))

            assert_equal(Git.rev_parse("master"), Git.get_config("branch.a.branchPoint"))
            assert_equal(Git.rev_parse("a"), Git.get_config("branch.b.branchPoint"))
          end
        end
      end

      def test_rebase_in_progress
        capture_io do
          with_test_repository("a-b-conflicts") do
            %x(git rebase --onto a b^ b)
            exception = assert_raises(Abort) do
              Rebase.new.call
            end

            assert_match(/rebase is in progress/, exception.message)
          end
        end
      end

      def test_rebase_merged
        capture_io do
          with_test_repository("a-b-chain") do
            Rebase.new.call

            Git.exec("checkout", "master")
            Git.exec("merge", "a")

            assert_equal(Git.rev_parse("master"), Git.rev_parse("a"))

            Git.exec("checkout", "a")
            Rebase.new.call

            assert_equal(Git.rev_parse("master"), Git.rev_parse("a"))
          end
        end
      end

      def test_rebase_moved
        capture_io do
          with_test_repository("a-b-chain") do
            Rebase.new.call

            a = Git.rev_parse("a")

            Git.exec("checkout", "a")
            Git.exec("commit", "-m", "message", "--allow-empty")
            new_a = Git.rev_parse("a")

            Git.exec("rebase", "--keep-empty", "--onto", "a", a, "b")
            assert_equal(new_a, Git.rev_parse("b~2"))

            Rebase.new.call
            assert_equal(new_a, Git.rev_parse("b~2"))
          end
        end
      end

      def test_fast_path_single_rebase_invocation
        with_test_repository("linear-chain") do
          Git.stubs(:supports_update_refs?).returns(true)
          out = nil
          with_rebase_recording do |calls|
            out, _ = capture_io { Rebase.new.call }

            assert_equal(1, calls.length)
            assert_includes(calls.first, "--update-refs")

            assert_equal(["a.1"], commit_subjects("master..a"))
            assert_equal(["b.1"], commit_subjects("a..b"))
            assert_equal(["c.1"], commit_subjects("b..c"))

            assert_equal(Git.rev_parse("master"), Git.get_config("branch.a.branchPoint"))
            assert_equal(Git.rev_parse("a"), Git.get_config("branch.b.branchPoint"))
            assert_equal(Git.rev_parse("b"), Git.get_config("branch.c.branchPoint"))
          end

          assert_match(/Auto-forwarding.*a.*master/, out)
        end
      end

      def test_fallback_when_head_on_middle_branch
        capture_io do
          with_test_repository("linear-chain") do
            with_rebase_recording do |calls|
              Git.exec("checkout", "b")
              Rebase.new.call

              # git skips refs that were checked out when the rebase started,
              # so a middle branch checked out here forces the fallback
              assert_equal(3, calls.length)
              calls.each { |args| refute_includes(args, "--update-refs") }

              assert_equal("c", Git.current_branch)
              assert_equal(["c.1"], commit_subjects("b..c"))
              assert_equal(Git.rev_parse("b"), Git.get_config("branch.c.branchPoint"))
            end
          end
        end
      end

      def test_fallback_when_git_too_old
        capture_io do
          with_test_repository("linear-chain") do
            Git.stubs(:supports_update_refs?).returns(false)
            with_rebase_recording do |calls|
              Rebase.new.call

              assert_equal(3, calls.length)
              calls.each { |args| refute_includes(args, "--update-refs") }

              assert_equal(["a.1"], commit_subjects("master..a"))
              assert_equal(["b.1"], commit_subjects("a..b"))
              assert_equal(["c.1"], commit_subjects("b..c"))

              assert_equal(Git.rev_parse("master"), Git.get_config("branch.a.branchPoint"))
              assert_equal(Git.rev_parse("a"), Git.get_config("branch.b.branchPoint"))
              assert_equal(Git.rev_parse("b"), Git.get_config("branch.c.branchPoint"))
            end
          end
        end
      end

      def test_fallback_for_non_nested_chain
        capture_io do
          with_test_repository("a-b-c-chain") do
            with_rebase_recording do |calls|
              Rebase.new.call

              calls.each { |args| refute_includes(args, "--update-refs") }

              assert_equal(Git.rev_parse("master"), Git.merge_base("master", "a"))
              assert_equal(Git.rev_parse("a"), Git.merge_base("a", "b"))
              assert_equal(Git.rev_parse("b"), Git.merge_base("b", "c"))

              assert_equal(Git.rev_parse("master"), Git.get_config("branch.a.branchPoint"))
              assert_equal(Git.rev_parse("a"), Git.get_config("branch.b.branchPoint"))
              assert_equal(Git.rev_parse("b"), Git.get_config("branch.c.branchPoint"))
            end
          end
        end
      end

      def test_fallback_when_foreign_branch_points_into_range
        capture_io do
          with_test_repository("linear-chain") do
            # scratch points at a.1, a commit inside the replayed range
            Git.exec("branch", "scratch", "b~1")
            scratch_before = Git.rev_parse("scratch")

            with_rebase_recording do |calls|
              Rebase.new.call

              calls.each { |args| refute_includes(args, "--update-refs") }
              assert_equal(scratch_before, Git.rev_parse("scratch"))

              assert_equal(["a.1"], commit_subjects("master..a"))
              assert_equal(["b.1"], commit_subjects("a..b"))
              assert_equal(["c.1"], commit_subjects("b..c"))
            end
          end
        end
      end

      def test_fallback_when_branch_checked_out_in_worktree
        capture_io do
          with_test_repository("linear-chain") do
            Git.exec("worktree", "add", ".worktrees/b", "b")
            configs_before = ["a", "b", "c"].to_h { |branch| [branch, Git.get_config("branch.#{branch}.branchPoint")] }

            with_rebase_recording do |calls|
              assert_raises(AbortSilent) do
                Rebase.new.call
              end

              calls.each { |args| refute_includes(args, "--update-refs") }

              # no branchPoint config is written when the rebase fails
              configs_after = ["a", "b", "c"].to_h { |branch| [branch, Git.get_config("branch.#{branch}.branchPoint")] }
              assert_equal(configs_before, configs_after)
            end
          end
        end
      end

      def test_verification_failure_aborts_without_writing_configs
        capture_io do
          with_test_repository("linear-chain") do
            Git.stubs(:supports_update_refs?).returns(true)
            configs_before = ["a", "b", "c"].to_h { |branch| [branch, Git.get_config("branch.#{branch}.branchPoint")] }

            # Eligibility and auto-forward checks pass; verification fails.
            Git.stubs(:ancestor?).returns(true, true, true, false)

            assert_raises(AbortSilent) do
              Rebase.new.call
            end

            configs_after = ["a", "b", "c"].to_h { |branch| [branch, Git.get_config("branch.#{branch}.branchPoint")] }
            assert_equal(configs_before, configs_after)
          end
        end
      end

      def test_fallback_for_diverged_chain
        capture_io do
          with_test_repository("linear-chain") do
            # Amend a's commit after b was created, leaving b with the old version
            Git.exec("checkout", "a")
            Git.exec("commit", "--amend", "-m", "a.1-amended", "--allow-empty")
            Git.exec("checkout", "c")

            with_rebase_recording do |calls|
              Rebase.new.call

              calls.each { |args| refute_includes(args, "--update-refs") }

              assert_equal(["a.1-amended"], commit_subjects("master..a"))
              assert_equal(["b.1"], commit_subjects("a..b"))
              assert_equal(["c.1"], commit_subjects("b..c"))
            end
          end
        end
      end

      def test_fast_path_conflict_continue_then_rerun
        capture_io do
          with_test_repository("linear-chain-conflicts") do
            Git.stubs(:supports_update_refs?).returns(true)
            with_rebase_recording do |calls|
              branch_point_before = Git.get_config("branch.a.branchPoint")

              assert_raises(AbortSilent) do
                Rebase.new.call
              end

              assert_equal(1, calls.length)
              assert_includes(calls.first, "--update-refs")
              assert(Git.rebase_in_progress?)
              assert_equal(branch_point_before, Git.get_config("branch.a.branchPoint"))

              File.write("shared.txt", "resolved\n")
              Git.exec("add", "shared.txt")
              Git.exec("commit", "--no-edit")
              Git.exec("rebase", "--continue")
              refute(Git.rebase_in_progress?)

              # Refs moved with subjects preserved, configs not yet refreshed
              assert_equal(["a.1"], commit_subjects("master..a"))
              assert_equal(["b.1"], commit_subjects("a..b"))
              assert_equal(["c.1"], commit_subjects("b..c"))
              assert_equal(branch_point_before, Git.get_config("branch.a.branchPoint"))

              Rebase.new.call

              assert_equal(Git.rev_parse("master"), Git.get_config("branch.a.branchPoint"))
              assert_equal(Git.rev_parse("a"), Git.get_config("branch.b.branchPoint"))
              assert_equal(Git.rev_parse("b"), Git.get_config("branch.c.branchPoint"))
              assert_equal(["c.1"], commit_subjects("b..c"))
            end
          end
        end
      end

      def test_fast_path_conflict_abort_restores_refs
        capture_io do
          with_test_repository("linear-chain-conflicts") do
            Git.stubs(:supports_update_refs?).returns(true)
            refs_before = ["a", "b", "c"].to_h { |branch| [branch, Git.rev_parse(branch)] }

            assert_raises(AbortSilent) do
              Rebase.new.call
            end

            Git.exec("rebase", "--abort")

            ["a", "b", "c"].each do |branch|
              assert_equal(refs_before[branch], Git.rev_parse(branch))
            end
            refute(Git.rebase_in_progress?)
          end
        end
      end

      private

      def commit_subjects(range)
        Git.exec("log", "--format=%s", range).split("\n")
      end
    end
  end
end
