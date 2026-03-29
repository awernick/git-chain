# frozen_string_literal: true

require "test_helper"

module GitChain
  module Commands
    class StatusTest < Minitest::Test
      include RepositoryTestHelper

      def test_status_shows_chain_name
        with_test_repository("a-b-chain") do
          out, _ = capture_io do
            Status.new.call(["--no-pr"])
          end

          assert_match(/default/, out)
        end
      end

      def test_status_shows_all_branches
        with_test_repository("a-b-chain") do
          out, _ = capture_io do
            Status.new.call(["--no-pr"])
          end

          assert_match(/master/, out)
          assert_match(/a/, out)
          assert_match(/b/, out)
        end
      end

      def test_status_shows_current_branch_marker
        with_test_repository("a-b-chain") do
          # Fixture ends on branch 'b'
          out, _ = capture_io do
            Status.new.call(["--no-pr"])
          end

          assert_match(/b.*HEAD/, out)
        end
      end

      def test_status_shows_tree_connectors
        with_test_repository("a-b-chain") do
          out, _ = capture_io do
            Status.new.call(["--no-pr"])
          end

          # Middle branch gets a tee connector
          assert_match(/\u251C\u2500\u2500/, out)
          # Last branch gets an elbow connector
          assert_match(/\u2514\u2500\u2500/, out)
        end
      end

      def test_status_shows_ahead_count
        with_test_repository("a-b-chain") do
          # Each branch has commits ahead of its parent's branch point
          out, _ = capture_io do
            Status.new.call(["--no-pr"])
          end

          assert_match(/ahead/, out)
        end
      end

      def test_status_with_chain_name_option
        with_test_repository("a-b-chain") do
          out, _ = capture_io do
            Status.new.call(["-c", "default", "--no-pr"])
          end

          assert_match(/default/, out)
          assert_match(/master/, out)
        end
      end

      def test_status_raises_when_not_in_chain
        with_test_repository("a-b") do
          capture_io do
            err = assert_raises(Abort) do
              Status.new.call(["--no-pr"])
            end
            assert_match(/not in a chain/, err.message)
          end
        end
      end

      def test_status_no_pr_flag_skips_pr_lookup
        with_test_repository("a-b-chain") do
          # Should not call gh at all
          Status.any_instance.expects(:fetch_pr_info).never

          out, _ = capture_io do
            Status.new.call(["--no-pr"])
          end

          # Should still render branch info
          assert_match(/master/, out)
        end
      end
    end
  end
end
