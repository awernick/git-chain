# frozen_string_literal: true

require "test_helper"

module GitChain
  module Commands
    class BranchTest < Minitest::Test
      include RepositoryTestHelper

      def test_append
        capture_io do
          with_test_repository("a-b-chain") do
            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b"], chain.branch_names)

            Branch.new.call(["c"])

            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b", "c"], chain.branch_names)

            assert_equal("b", chain.branches[3].parent_branch)
            assert_equal(Git.rev_parse("b"), chain.branches[3].branch_point)
            assert_equal("c", Git.current_branch)
          end
        end
      end

      def test_insert_chain
        capture_io do
          with_test_repository("a-b-chain") do
            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b"], chain.branch_names)

            Branch.new.call(["a", "c", "--insert"])

            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "c", "b"], chain.branch_names)

            c = chain.branches[2]
            assert_equal("a", c.parent_branch)
            assert_equal(Git.rev_parse("a"), c.branch_point)

            b = chain.branches[3]
            assert_equal("c", b.parent_branch)
            # Auto-rebase updates branch_point to the new parent's tip
            assert_equal(Git.rev_parse("c"), b.branch_point)
          end
        end
      end

      def test_new_middle_of_chain
        capture_io do
          with_test_repository("a-b-chain") do
            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b"], chain.branch_names)

            Branch.new.call(["a", "c"])

            chain = Models::Chain.from_config("c")
            assert_equal(["a", "c"], chain.branch_names)

            c = chain.branches[1]
            assert_equal("a", c.parent_branch)
            assert_equal(Git.rev_parse("a"), c.branch_point)
          end
        end
      end

      def test_new_end_of_chain
        capture_io do
          with_test_repository("a-b-chain") do
            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b"], chain.branch_names)

            Branch.new.call(["c", "--new"])

            chain = Models::Chain.from_config("c")
            assert_equal(["b", "c"], chain.branch_names)

            assert_equal("b", chain.branches[1].parent_branch)
            assert_equal(Git.rev_parse("b"), chain.branches[1].branch_point)
          end
        end
      end

      def test_branch_outside_of_chain
        capture_io do
          with_test_repository("a-b-chain") do
            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b"], chain.branch_names)

            Git.exec("checkout", "a", "-b", "c")
            Git.exec("commit", "--allow-empty", "-m", "c")

            Branch.new.call(["c", "d"])

            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b"], chain.branch_names)

            chain = Models::Chain.from_config("d")
            assert_equal(["c", "d"], chain.branch_names)
          end
        end
      end

      # -- --after flag --

      def test_after_appends_to_end
        capture_io do
          with_test_repository("a-b-chain") do
            Branch.new.call(["c", "--after", "b"])

            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "b", "c"], chain.branch_names)
            assert_equal("b", chain.branches[3].parent_branch)
            assert_equal("c", Git.current_branch)
          end
        end
      end

      def test_after_inserts_in_middle
        capture_io do
          with_test_repository("a-b-chain") do
            Branch.new.call(["c", "--after", "a"])

            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "c", "b"], chain.branch_names)

            c = chain.branches[2]
            assert_equal("a", c.parent_branch)
            assert_equal("c", Git.current_branch)

            b = chain.branches[3]
            assert_equal("c", b.parent_branch)
            # Auto-rebase updates branch_point
            assert_equal(Git.rev_parse("c"), b.branch_point)
          end
        end
      end

      def test_after_base_branch
        capture_io do
          with_test_repository("a-b-chain") do
            Branch.new.call(["c", "--after", "master"])

            chain = Models::Chain.from_config("default")
            assert_equal(["master", "c", "a", "b"], chain.branch_names)

            c = chain.branches[1]
            assert_equal("master", c.parent_branch)
            assert_equal("c", Git.current_branch)
          end
        end
      end

      def test_after_invalid_branch
        capture_io do
          with_test_repository("a-b-chain") do
            err = assert_raises(Abort) do
              Branch.new.call(["c", "--after", "nonexistent"])
            end
            assert_match(/not a branch/, err.message)
          end
        end
      end

      # -- --before flag --

      def test_before_inserts_before_target
        capture_io do
          with_test_repository("a-b-chain") do
            Branch.new.call(["c", "--before", "b"])

            chain = Models::Chain.from_config("default")
            assert_equal(["master", "a", "c", "b"], chain.branch_names)

            c = chain.branches[2]
            assert_equal("a", c.parent_branch)
            assert_equal("c", Git.current_branch)

            b = chain.branches[3]
            assert_equal("c", b.parent_branch)
            assert_equal(Git.rev_parse("c"), b.branch_point)
          end
        end
      end

      def test_before_first_branch
        capture_io do
          with_test_repository("a-b-chain") do
            Branch.new.call(["c", "--before", "a"])

            chain = Models::Chain.from_config("default")
            assert_equal(["master", "c", "a", "b"], chain.branch_names)

            c = chain.branches[1]
            assert_equal("master", c.parent_branch)
            assert_equal("c", Git.current_branch)
          end
        end
      end

      def test_before_base_branch_raises
        capture_io do
          with_test_repository("a-b-chain") do
            err = assert_raises(Abort) do
              Branch.new.call(["c", "--before", "master"])
            end
            assert_match(/Cannot insert before the base branch/, err.message)
          end
        end
      end

      def test_before_invalid_branch
        capture_io do
          with_test_repository("a-b-chain") do
            err = assert_raises(Abort) do
              Branch.new.call(["c", "--before", "nonexistent"])
            end
            assert_match(/not in any chain/, err.message)
          end
        end
      end

      # -- Validation --

      def test_branch_already_exists
        capture_io do
          with_test_repository("a-b-chain") do
            Git.exec("checkout", "-b", "c")
            Git.exec("checkout", "b")

            err = assert_raises(Abort) do
              Branch.new.call(["c"])
            end
            assert_match(/already exists/, err.message)
          end
        end
      end

      def test_after_and_before_mutually_exclusive
        capture_io do
          with_test_repository("a-b-chain") do
            assert_raises(AbortSilent) do
              Branch.new.call(["c", "--after", "a", "--before", "b"])
            end
          end
        end
      end

      def test_after_with_insert_raises
        capture_io do
          with_test_repository("a-b-chain") do
            assert_raises(AbortSilent) do
              Branch.new.call(["c", "--after", "a", "--insert"])
            end
          end
        end
      end

      def test_after_with_new_raises
        capture_io do
          with_test_repository("a-b-chain") do
            assert_raises(AbortSilent) do
              Branch.new.call(["c", "--after", "a", "--new"])
            end
          end
        end
      end

      def test_after_with_chain_flag_validates
        capture_io do
          with_test_repository("a-b-chain") do
            err = assert_raises(Abort) do
              Branch.new.call(["c", "--after", "a", "--chain", "nonexistent"])
            end
            assert_match(/not in chain/, err.message)
          end
        end
      end
    end
  end
end
