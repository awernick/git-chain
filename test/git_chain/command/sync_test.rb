# frozen_string_literal: true

require "test_helper"

module GitChain
  module Commands
    class SyncTest < Minitest::Test
      include RepositoryTestHelper

      def mock_forge(branch_states)
        forge = mock("forge")
        forge.stubs(:cli_available?).returns(true)

        branch_states.each do |branch_name, state|
          pr_info = if state
            idx = branch_states.keys.index(branch_name)
            { number: idx + 100, state: state, is_draft: false, review_decision: nil, url: nil }
          end
          forge.stubs(:pr_for_branch).with(branch_name).returns(pr_info)
        end

        Forge.stubs(:detect).returns(forge)
        forge
      end

      def test_no_merged_branches
        with_test_repository("a-b-chain") do
          mock_forge("a" => "OPEN", "b" => "OPEN")

          out, _ = capture_io do
            Sync.new.call
          end

          assert_match(/No merged branches detected/, out)
          assert_equal(["master", "a", "b"], Models::Chain.from_config("default").branch_names)
        end
      end

      def test_sync_single_merged_branch
        with_test_repository("a-b-chain") do
          capture_io { Rebase.new.call }

          Git.exec("checkout", "master")
          Git.exec("merge", "a")
          Git.exec("checkout", "b")

          mock_forge("a" => "MERGED", "b" => "OPEN")

          out, _ = capture_io do
            Sync.new.call
          end

          assert_match(/Detected merged branch.*a/, out)
          assert_match(/Done/, out)

          chain = Models::Chain.from_config("default")
          assert_equal(["master", "b"], chain.branch_names)
        end
      end

      def test_sync_multiple_merged_branches
        with_test_repository("a-b-c-chain") do
          capture_io { Rebase.new.call }

          Git.exec("checkout", "master")
          Git.exec("merge", "a")
          Git.exec("merge", "b")
          Git.exec("checkout", "c")

          mock_forge("a" => "MERGED", "b" => "MERGED", "c" => "OPEN")

          out, _ = capture_io do
            Sync.new.call
          end

          assert_match(/Detected merged branch.*a/, out)
          assert_match(/Detected merged branch.*b/, out)
          assert_match(/Done/, out)

          chain = Models::Chain.from_config("default")
          assert_equal(["master", "c"], chain.branch_names)
        end
      end

      def test_sync_middle_branch_merged
        with_test_repository("a-b-c-chain") do
          capture_io { Rebase.new.call }

          # Merge only b (middle branch) into a
          Git.exec("checkout", "a")
          Git.exec("merge", "b")
          Git.exec("checkout", "c")

          mock_forge("a" => "OPEN", "b" => "MERGED", "c" => "OPEN")

          out, _ = capture_io do
            Sync.new.call
          end

          assert_match(/Detected merged branch.*b/, out)
          assert_match(/Done/, out)

          chain = Models::Chain.from_config("default")
          assert_equal(["master", "a", "c"], chain.branch_names)

          # Verify c's parent is now a
          branch_c = Models::Branch.from_config("c")
          assert_equal("a", branch_c.parent_branch)
        end
      end

      def test_dry_run
        with_test_repository("a-b-chain") do
          mock_forge("a" => "MERGED", "b" => "OPEN")

          out, _ = capture_io do
            Sync.new.call(["--dry-run"])
          end

          assert_match(/Would remove.*a/, out)
          assert_match(/Would rebase.*b.*onto.*master/, out)
          assert_match(/Remaining chain: master -> b/, out)

          # Chain should be unchanged
          assert_equal(["master", "a", "b"], Models::Chain.from_config("default").branch_names)
        end
      end

      def test_dry_run_multiple_merged
        with_test_repository("a-b-c-chain") do
          mock_forge("a" => "MERGED", "b" => "MERGED", "c" => "OPEN")

          out, _ = capture_io do
            Sync.new.call(["-n"])
          end

          assert_match(/Would remove.*a/, out)
          assert_match(/Would remove.*b/, out)
          assert_match(/Would rebase.*c.*onto.*master/, out)
          assert_match(/Remaining chain: master -> c/, out)

          # Chain should be unchanged
          assert_equal(["master", "a", "b", "c"], Models::Chain.from_config("default").branch_names)
        end
      end

      def test_all_branches_merged
        with_test_repository("a-b-chain") do
          capture_io { Rebase.new.call }

          Git.exec("checkout", "master")
          Git.exec("merge", "a")
          Git.exec("merge", "b")
          Git.exec("checkout", "b")

          mock_forge("a" => "MERGED", "b" => "MERGED")

          out, _ = capture_io do
            Sync.new.call
          end

          assert_match(/All branches.*have been merged/, out)
          assert_equal("master", Git.current_branch)

          # Config should be cleared for merged branches
          assert_nil(Git.get_config("branch.a.chain"))
          assert_nil(Git.get_config("branch.b.chain"))
        end
      end

      def test_no_forge_detected
        with_test_repository("a-b-chain") do
          Forge.stubs(:detect).returns(nil)

          err = assert_raises(Abort) do
            capture_io { Sync.new.call }
          end

          assert_match(/No forge detected/, err.message)
        end
      end

      def test_forge_cli_not_available
        with_test_repository("a-b-chain") do
          forge = mock("forge")
          forge.stubs(:cli_available?).returns(false)
          forge.stubs(:cli_command).returns("gh")
          Forge.stubs(:detect).returns(forge)

          err = assert_raises(Abort) do
            capture_io { Sync.new.call }
          end

          assert_match(/not available/, err.message)
        end
      end

      def test_rebase_in_progress
        with_test_repository("a-b-chain") do
          Git.stubs(:rebase_in_progress?).returns(true)

          err = assert_raises(Abort) do
            capture_io { Sync.new.call }
          end

          assert_match(/rebase is in progress/, err.message)
        end
      end

      def test_restores_current_branch
        with_test_repository("a-b-c-chain") do
          capture_io { Rebase.new.call }

          Git.exec("checkout", "master")
          Git.exec("merge", "a")

          # Start on c (which is not being removed)
          Git.exec("checkout", "c")

          mock_forge("a" => "MERGED", "b" => "OPEN", "c" => "OPEN")

          capture_io { Sync.new.call }

          assert_equal("c", Git.current_branch)
        end
      end

      def test_checks_out_last_branch_when_current_is_merged
        with_test_repository("a-b-chain") do
          capture_io { Rebase.new.call }

          Git.exec("checkout", "master")
          Git.exec("merge", "a")

          # Start on a (which is being removed)
          Git.exec("checkout", "a")

          mock_forge("a" => "MERGED", "b" => "OPEN")

          capture_io { Sync.new.call }

          # Should check out the last remaining branch
          assert_equal("b", Git.current_branch)
        end
      end

      def test_conflict_during_rebase
        with_test_repository("a-b-conflicts") do
          # Merge a into master (a has conflicting b.txt)
          Git.exec("merge", "a", "-m", "merge a into master")
          Git.exec("checkout", "b")

          mock_forge("a" => "MERGED", "b" => "OPEN")

          assert_raises(AbortSilent) do
            capture_io { Sync.new.call }
          end

          # Chain should be reconfigured even though rebase failed
          chain = Models::Chain.from_config("default")
          assert_equal(["master", "b"], chain.branch_names)

          # Rebase should be in progress
          assert(Git.rebase_in_progress?)
        end
      end

      def test_no_config_changes_on_merge_base_failure
        with_test_repository("a-b-c-chain") do
          mock_forge("a" => "MERGED", "b" => "OPEN", "c" => "OPEN")

          # Stub merge_base to fail on the second remaining branch
          Git.stubs(:merge_base).with("master", "b").returns(nil)

          err = assert_raises(Abort) do
            capture_io { Sync.new.call }
          end

          assert_match(/no common ancestor/, err.message)

          # Chain config should be unchanged
          assert_equal(["master", "a", "b", "c"], Models::Chain.from_config("default").branch_names)

          branch_b = Models::Branch.from_config("b")
          assert_equal("a", branch_b.parent_branch)
        end
      end

      def test_chain_name_option
        with_test_repository("a-b-chain") do
          capture_io { Rebase.new.call }

          Git.exec("checkout", "master")
          Git.exec("merge", "a")
          Git.exec("checkout", "master")

          mock_forge("a" => "MERGED", "b" => "OPEN")

          out, _ = capture_io do
            Sync.new.call(["-c", "default"])
          end

          assert_match(/Done/, out)
          assert_equal(["master", "b"], Models::Chain.from_config("default").branch_names)
        end
      end
    end
  end
end
