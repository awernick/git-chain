# frozen_string_literal: true
require "test_helper"

module GitChain
  module Commands
    class PushTest < Minitest::Test
      include RepositoryTestHelper

      def test_push_nothing
        capture_io do
          with_remote_test_repository("a-b-chain") do |_remote_repo|
            err = assert_raises(Abort) do
              Push.new.call
            end
            assert_equal("Nothing to push", err.message)
          end
        end
      end

      def test_push_upstream
        capture_io do
          with_remote_test_repository("a-b-chain") do |remote_repo|
            assert_empty(Git.branches(dir: remote_repo))
            assert_nil(Git.remote_name(branch: "a"))

            Push.new.call(["-u"])
            assert_equal(%w(a b).sort, Git.branches(dir: remote_repo).sort)

            assert_equal("test/a", Git.push_branch(branch: "a"))
            assert_equal("test", Git.remote_name(branch: "a"))
            assert_equal(remote_repo, Git.remote_url(branch: "a"))
          end
        end
      end

      def test_push_default_force_with_lease
        capture_io do
          with_remote_test_repository("a-b-chain") do |_remote_repo|
            Push.new.call(["-u"])

            Git.exec("checkout", "b")
            Git.exec("commit", "--amend", "--allow-empty", "-m", "amended")

            # Default push uses --force-with-lease, should succeed on diverged history
            Push.new.call
          end
        end
      end

      def test_push_no_force_fails_on_diverged
        capture_io do
          with_remote_test_repository("a-b-chain") do |_remote_repo|
            Push.new.call(["-u"])

            Git.exec("checkout", "b")
            Git.exec("commit", "--amend", "--allow-empty", "-m", "amended")

            err = assert_raises(Abort) do
              Push.new.call(["--no-force"])
            end
            assert_match(/Failed to push/, err.message)
            assert_match(/b/, err.message)
          end
        end
      end

      def test_push_hard_force
        capture_io do
          with_remote_test_repository("a-b-chain") do |_remote_repo|
            Push.new.call(["-u"])

            Git.exec("checkout", "b")
            Git.exec("commit", "--amend", "--allow-empty", "-m", "amended")

            # Hard force should succeed
            Push.new.call(["-f"])
          end
        end
      end

      def test_push_dry_run_does_not_push
        capture_io do
          with_remote_test_repository("a-b-chain") do |remote_repo|
            Push.new.call(["-u"])

            original_sha = Git.exec("rev-parse", "refs/heads/b", dir: remote_repo)

            Git.exec("checkout", "b")
            Git.exec("commit", "--amend", "--allow-empty", "-m", "amended")

            local_sha = Git.exec("rev-parse", "b")
            refute_equal(original_sha, local_sha)

            # Dry run should not push but should show status
            out, _ = capture_io do
              Push.new.call(["--dry-run"])
            end

            # Remote should still have original SHA
            remote_sha = Git.exec("rev-parse", "refs/heads/b", dir: remote_repo)
            assert_equal(original_sha, remote_sha)

            # Should report force mode and per-branch status
            assert_match(/force-with-lease/, out)
            assert_match(/a.*up-to-date/, out)
            assert_match(/b.*diverged/, out)
          end
        end
      end

      def test_push_continues_on_failure
        capture_io do
          with_remote_test_repository("a-b-chain") do |remote_repo|
            Push.new.call(["-u"])

            # Add a new commit to 'a' (ahead, fast-forward possible)
            Git.exec("checkout", "a")
            Git.exec("commit", "--allow-empty", "-m", "new commit on a")

            # Amend 'b' (diverged from remote)
            Git.exec("checkout", "b")
            Git.exec("commit", "--amend", "--allow-empty", "-m", "amended b")

            # Push with --no-force: a should succeed (fast-forward), b should fail (diverged)
            err = assert_raises(Abort) do
              Push.new.call(["--no-force"])
            end
            assert_match(/b/, err.message)
            refute_match(/\ba\b/, err.message)

            # Verify a was pushed successfully despite b failing
            remote_a_sha = Git.exec("rev-parse", "refs/heads/a", dir: remote_repo)
            local_a_sha = Git.exec("rev-parse", "a")
            assert_equal(local_a_sha, remote_a_sha)
          end
        end
      end

      def test_push_skips_up_to_date_branches
        capture_io do
          with_remote_test_repository("a-b-chain") do |_remote_repo|
            Push.new.call(["-u"])

            # Push again without changes: all branches should be up-to-date
            Push.new.call
          end
        end
      end

      private

      def with_remote_test_repository(fixture_name, remote: "test")
        Dir.mktmpdir("git-chain-rebase") do |dir|
          Git.exec("init", "--bare", dir)

          with_test_repository(fixture_name) do
            Git.exec("remote", "add", remote, dir)
            yield(dir)
          end
        end
      end
    end
  end
end
