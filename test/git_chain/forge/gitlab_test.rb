# frozen_string_literal: true

require "test_helper"

module GitChain
  module Forge
    class GitlabTest < Minitest::Test
      def test_normalize_opened_state
        gitlab = Gitlab.new
        mr = gitlab.send(:normalize, {
          "iid" => 42,
          "state" => "opened",
          "draft" => false,
          "web_url" => "https://gitlab.com/user/repo/-/merge_requests/42",
        })

        assert_equal(42, mr[:number])
        assert_equal("OPEN", mr[:state])
        refute(mr[:is_draft])
        assert_nil(mr[:review_decision])
        assert_equal("https://gitlab.com/user/repo/-/merge_requests/42", mr[:url])
      end

      def test_normalize_merged_state
        gitlab = Gitlab.new
        mr = gitlab.send(:normalize, {
          "iid" => 10,
          "state" => "merged",
          "draft" => false,
          "web_url" => "https://gitlab.com/user/repo/-/merge_requests/10",
        })

        assert_equal("MERGED", mr[:state])
        assert_equal("https://gitlab.com/user/repo/-/merge_requests/10", mr[:url])
      end

      def test_normalize_closed_state
        gitlab = Gitlab.new
        mr = gitlab.send(:normalize, {
          "iid" => 3,
          "state" => "closed",
          "draft" => false,
          "web_url" => "https://gitlab.com/user/repo/-/merge_requests/3",
        })

        assert_equal("CLOSED", mr[:state])
        assert_equal("https://gitlab.com/user/repo/-/merge_requests/3", mr[:url])
      end

      def test_normalize_draft_mr
        gitlab = Gitlab.new
        mr = gitlab.send(:normalize, {
          "iid" => 7,
          "state" => "opened",
          "draft" => true,
          "web_url" => "https://gitlab.com/user/repo/-/merge_requests/7",
        })

        assert(mr[:is_draft])
        assert_equal("https://gitlab.com/user/repo/-/merge_requests/7", mr[:url])
      end

      def test_normalize_missing_draft_field
        gitlab = Gitlab.new
        mr = gitlab.send(:normalize, {
          "iid" => 7,
          "state" => "opened",
        })

        refute(mr[:is_draft])
        assert_nil(mr[:url])
      end

      def test_review_decision_always_nil
        gitlab = Gitlab.new
        mr = gitlab.send(:normalize, {
          "iid" => 1,
          "state" => "opened",
          "draft" => false,
          "web_url" => "https://gitlab.com/user/repo/-/merge_requests/1",
        })

        assert_nil(mr[:review_decision])
        assert_equal("https://gitlab.com/user/repo/-/merge_requests/1", mr[:url])
      end
    end
  end
end
