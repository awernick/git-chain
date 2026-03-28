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
  end
end
