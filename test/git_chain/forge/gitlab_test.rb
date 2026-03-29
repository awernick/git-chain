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
        })

        assert_equal(42, mr[:number])
        assert_equal("OPEN", mr[:state])
        assert_equal(false, mr[:is_draft])
        assert_nil(mr[:review_decision])
      end

      def test_normalize_merged_state
        gitlab = Gitlab.new
        mr = gitlab.send(:normalize, {
          "iid" => 10,
          "state" => "merged",
          "draft" => false,
        })

        assert_equal("MERGED", mr[:state])
      end

      def test_normalize_closed_state
        gitlab = Gitlab.new
        mr = gitlab.send(:normalize, {
          "iid" => 3,
          "state" => "closed",
          "draft" => false,
        })

        assert_equal("CLOSED", mr[:state])
      end

      def test_normalize_draft_mr
        gitlab = Gitlab.new
        mr = gitlab.send(:normalize, {
          "iid" => 7,
          "state" => "opened",
          "draft" => true,
        })

        assert_equal(true, mr[:is_draft])
      end

      def test_normalize_missing_draft_field
        gitlab = Gitlab.new
        mr = gitlab.send(:normalize, {
          "iid" => 7,
          "state" => "opened",
        })

        assert_equal(false, mr[:is_draft])
      end

      def test_review_decision_always_nil
        gitlab = Gitlab.new
        mr = gitlab.send(:normalize, {
          "iid" => 1,
          "state" => "opened",
          "draft" => false,
        })

        assert_nil(mr[:review_decision])
      end
    end
  end
end
