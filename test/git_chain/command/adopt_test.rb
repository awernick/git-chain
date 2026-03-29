# frozen_string_literal: true

require "test_helper"

module GitChain
  module Commands
    class AdoptTest < Minitest::Test
      include RepositoryTestHelper

      def test_adopt_append
        capture_io do
          with_test_repository("a-b-chain") do
            Git.exec("checkout", "-b", "c", "b")
            Git.exec("commit", "--allow-empty", "-m", "c.1")
            Git.exec("checkout", "b")

            Adopt.new.call(["c"])

            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b", "c"], chain.branch_names)
            assert_equal("b", chain.branches[3].parent_branch)
            assert_equal("default", chain.branches[3].chain_name)
          end
        end
      end

      def test_adopt_after
        capture_io do
          with_test_repository("a-b-chain") do
            Git.exec("checkout", "-b", "c", "b")
            Git.exec("commit", "--allow-empty", "-m", "c.1")
            Git.exec("checkout", "b")

            Adopt.new.call(["c", "--after", "a"])

            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "c", "b"], chain.branch_names)
            assert_equal("a", chain.branches[2].parent_branch)
          end
        end
      end

      def test_adopt_current_branch
        capture_io do
          with_test_repository("a-b-chain") do
            Git.exec("checkout", "-b", "c", "b")
            Git.exec("commit", "--allow-empty", "-m", "c.1")

            # Don't pass branch name; should adopt current branch (c)
            Adopt.new.call(["--after", "b"])

            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b", "c"], chain.branch_names)
            assert_equal("b", chain.branches[3].parent_branch)
          end
        end
      end

      def test_adopt_with_chain_flag
        capture_io do
          with_test_repository("a-b-chain") do
            Git.exec("checkout", "-b", "c", "b")
            Git.exec("commit", "--allow-empty", "-m", "c.1")
            Git.exec("checkout", "b")

            Adopt.new.call(["c", "-c", "default"])

            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b", "c"], chain.branch_names)
          end
        end
      end

      def test_adopt_nonexistent_branch
        capture_io do
          with_test_repository("a-b-chain") do
            err = assert_raises(Abort) do
              Adopt.new.call(["nonexistent"])
            end
            assert_match(/does not exist/, err.message)
          end
        end
      end

      def test_adopt_already_in_same_chain
        capture_io do
          with_test_repository("a-b-chain") do
            err = assert_raises(Abort) do
              Adopt.new.call(["a"])
            end
            assert_match(/already in chain/, err.message)
          end
        end
      end

      def test_adopt_already_in_different_chain
        capture_io do
          with_test_repository("a-b-chain") do
            Git.exec("checkout", "-b", "c", "b")
            Git.exec("commit", "--allow-empty", "-m", "c.1")
            Git.exec("checkout", "b")

            Setup.new.call(["--chain", "other", "b", "c"])

            err = assert_raises(Abort) do
              Adopt.new.call(["c"])
            end
            assert_match(/already in chain 'other'/, err.message)
            assert_match(/--force/, err.message)
          end
        end
      end

      def test_adopt_force_move
        capture_io do
          with_test_repository("a-b-chain") do
            Git.exec("checkout", "-b", "c", "b")
            Git.exec("commit", "--allow-empty", "-m", "c.1")
            Git.exec("checkout", "b")

            Setup.new.call(["--chain", "other", "b", "c"])

            # Verify c is in "other"
            other = Models::Chain.from_config("other")
            assert_equal(["b", "c"], other.branch_names)

            Adopt.new.call(["c", "--force"])

            # c should now be in default
            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b", "c"], chain.branch_names)

            # "other" chain should be gone (only base left)
            c_branch = Models::Branch.from_config("c")
            assert_equal("default", c_branch.chain_name)
          end
        end
      end

      def test_adopt_force_move_from_middle
        capture_io do
          with_test_repository("a-b-chain") do
            Git.exec("checkout", "-b", "c", "b")
            Git.exec("commit", "--allow-empty", "-m", "c.1")
            Git.exec("checkout", "-b", "d", "c")
            Git.exec("commit", "--allow-empty", "-m", "d.1")
            Git.exec("checkout", "b")

            Setup.new.call(["--chain", "other", "b", "c", "d"])

            Adopt.new.call(["c", "--force"])

            # default chain gets c appended
            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b", "c"], chain.branch_names)

            # "other" chain should re-parent d to b
            other = Models::Chain.from_config("other")
            assert_equal(["b", "d"], other.branch_names)
            assert_equal("b", other.branches[1].parent_branch)
          end
        end
      end

      def test_adopt_force_base_branch_raises
        capture_io do
          with_test_repository("a-b-chain") do
            Git.exec("checkout", "-b", "c", "b")
            Git.exec("commit", "--allow-empty", "-m", "c.1")
            Git.exec("checkout", "-b", "d", "c")
            Git.exec("commit", "--allow-empty", "-m", "d.1")
            Git.exec("checkout", "b")

            Setup.new.call(["--chain", "other", "c", "d"])

            # c is the base of "other"; adopting it with --force should fail
            err = assert_raises(Abort) do
              Adopt.new.call(["c", "--force"])
            end
            assert_match(/base branch/, err.message)
          end
        end
      end

      def test_adopt_with_rebase
        capture_io do
          with_test_repository("a-b-chain") do
            Git.exec("checkout", "-b", "c", "master")
            Git.exec("commit", "--allow-empty", "-m", "c.1")
            Git.exec("checkout", "b")

            Adopt.new.call(["c", "--after", "b", "--rebase"])

            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b", "c"], chain.branch_names)

            c_branch = chain.branches[3]
            assert_equal("b", c_branch.parent_branch)
            assert_equal(Git.rev_parse("b"), c_branch.branch_point)
          end
        end
      end

      def test_adopt_without_rebase
        capture_io do
          with_test_repository("a-b-chain") do
            Git.exec("checkout", "-b", "c", "master")
            Git.exec("commit", "--allow-empty", "-m", "c.1")
            Git.exec("checkout", "b")

            Adopt.new.call(["c", "--after", "b"])

            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b", "c"], chain.branch_names)

            c_branch = chain.branches[3]
            assert_equal("b", c_branch.parent_branch)
            # Without rebase, branch_point is the merge-base of b and c,
            # NOT rev_parse("b") since c was branched from master
            merge_base = Git.merge_base("b", "c")
            assert_equal(merge_base, c_branch.branch_point)
            refute_equal(Git.rev_parse("b"), c_branch.branch_point)
          end
        end
      end

      def test_adopt_after_nonexistent
        capture_io do
          with_test_repository("a-b-chain") do
            Git.exec("checkout", "-b", "c", "b")
            Git.exec("commit", "--allow-empty", "-m", "c.1")
            Git.exec("checkout", "b")

            err = assert_raises(Abort) do
              Adopt.new.call(["c", "--after", "nonexistent"])
            end
            assert_match(/is not a branch/, err.message)
          end
        end
      end

      def test_adopt_after_not_in_chain
        capture_io do
          with_test_repository("a-b-chain") do
            Git.exec("checkout", "-b", "c", "b")
            Git.exec("commit", "--allow-empty", "-m", "c.1")
            Git.exec("checkout", "-b", "d", "b")
            Git.exec("commit", "--allow-empty", "-m", "d.1")
            Git.exec("checkout", "b")

            err = assert_raises(Abort) do
              Adopt.new.call(["c", "--after", "d"])
            end
            assert_match(/not in any chain/, err.message)
          end
        end
      end

      def test_adopt_rebase_in_progress
        capture_io do
          with_test_repository("a-b-chain") do
            Git.exec("checkout", "-b", "c", "b")
            Git.exec("commit", "--allow-empty", "-m", "c.1")
            Git.exec("checkout", "b")

            # Simulate rebase-in-progress
            FileUtils.mkdir_p(".git/rebase-merge")

            err = assert_raises(Abort) do
              Adopt.new.call(["c"])
            end
            assert_match(/rebase is in progress/, err.message)
          end
        end
      end

      def test_adopt_too_many_arguments
        capture_io do
          with_test_repository("a-b-chain") do
            assert_raises(AbortSilent) do
              Adopt.new.call(["c", "d"])
            end
          end
        end
      end
    end
  end
end
