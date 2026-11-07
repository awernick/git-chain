# frozen_string_literal: true

require "test_helper"

module GitChain
  class GitTest < Minitest::Test
    include RepositoryTestHelper

    def test_chains
      with_test_repository("a-b-chain") do
        assert_equal({ "a" => "default", "b" => "default" }, Git.chains)
      end
    end

    def test_ahead_behind
      with_test_repository("a-b-chain") do
        counts = Git.ahead_behind("a", "master")
        assert_instance_of(Hash, counts)
        assert(counts[:ahead] >= 0)
        assert(counts[:behind] >= 0)
      end
    end

    def test_ahead_behind_invalid_ref
      with_test_repository("a-b-chain") do
        result = Git.ahead_behind("nonexistent", "master")
        assert_nil(result)
      end
    end

    def test_git_version_parses_version_output
      Git.reset_version_cache
      Git.stubs(:exec).with("version").returns("git version 2.43.0\n")

      assert_equal("2.43.0", Git.git_version)
    ensure
      Git.reset_version_cache
    end

    def test_supports_update_refs_when_git_new_enough
      Git.reset_version_cache
      Git.stubs(:exec).with("version").returns("git version 2.38.0\n")

      assert(Git.supports_update_refs?)
    ensure
      Git.reset_version_cache
    end

    def test_supports_update_refs_when_git_too_old
      Git.reset_version_cache
      Git.stubs(:exec).with("version").returns("git version 2.37.5\n")

      refute(Git.supports_update_refs?)
    ensure
      Git.reset_version_cache
    end

    def test_supports_update_refs_compares_numerically
      Git.reset_version_cache
      Git.stubs(:exec).with("version").returns("git version 2.37.50\n")
      refute(Git.supports_update_refs?)

      Git.reset_version_cache
      Git.stubs(:exec).with("version").returns("git version 2.38.0.1\n")
      assert(Git.supports_update_refs?)

      Git.reset_version_cache
      Git.stubs(:exec).with("version").returns("git version 2.38\n")
      assert(Git.supports_update_refs?)
    ensure
      Git.reset_version_cache
    end

    def test_supports_update_refs_when_version_unavailable
      Git.reset_version_cache
      Git.stubs(:exec).with("version").raises(Git::Failure.new(["version"], "not a git repository"))

      refute(Git.supports_update_refs?)
    ensure
      Git.reset_version_cache
    end

    def test_other_worktree_branches
      with_test_repository("a-b-chain") do
        assert_equal([], Git.other_worktree_branches)
      end
    end

    def test_other_worktree_branches_with_linked_worktree
      with_test_repository("a-b-chain") do
        Git.exec("worktree", "add", ".worktrees/a", "a")

        assert_equal(["refs/heads/a"], Git.other_worktree_branches)
      end
    end
  end
end
