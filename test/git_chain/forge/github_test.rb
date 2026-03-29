# frozen_string_literal: true

require "test_helper"

module GitChain
  module Forge
    class GithubTest < Minitest::Test
      def test_cli_available
        skip("gh not installed") unless gh_available?
        github = Github.new
        assert(github.cli_available?)
      end

      def test_pr_for_branch_no_match
        skip("gh not installed") unless gh_available?
        github = Github.new
        result = github.pr_for_branch("nonexistent-branch-abc123xyz")
        assert_nil(result)
      end

      def test_normalize_open_pr
        github = Github.new
        pr = github.send(:normalize, {
          "number" => 42,
          "state" => "OPEN",
          "isDraft" => false,
          "reviewDecision" => "APPROVED",
        })

        assert_equal(42, pr[:number])
        assert_equal("OPEN", pr[:state])
        refute(pr[:is_draft])
        assert_equal("APPROVED", pr[:review_decision])
      end

      def test_normalize_merged_pr
        github = Github.new
        pr = github.send(:normalize, {
          "number" => 10,
          "state" => "MERGED",
          "isDraft" => false,
          "reviewDecision" => nil,
        })

        assert_equal("MERGED", pr[:state])
      end

      def test_normalize_draft_pr
        github = Github.new
        pr = github.send(:normalize, {
          "number" => 5,
          "state" => "OPEN",
          "isDraft" => true,
          "reviewDecision" => nil,
        })

        assert(pr[:is_draft])
      end

      private

      def gh_available?
        _, _, stat = Open3.capture3("gh", "--version")
        stat.success?
      rescue Errno::ENOENT
        false
      end
    end
  end
end
