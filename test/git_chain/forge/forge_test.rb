# frozen_string_literal: true
require "test_helper"

module GitChain
  module Forge
    class ForgeTest < Minitest::Test
      include RepositoryTestHelper

      def test_detect_github_from_https_url
        forge = Forge.send(:from_remote_url, "https://github.com/user/repo.git")
        assert_instance_of(Github, forge)
      end

      def test_detect_github_from_ssh_url
        forge = Forge.send(:from_remote_url, "git@github.com:user/repo.git")
        assert_instance_of(Github, forge)
      end

      def test_detect_gitlab_from_https_url
        forge = Forge.send(:from_remote_url, "https://gitlab.com/user/repo.git")
        assert_instance_of(Gitlab, forge)
      end

      def test_detect_gitlab_from_ssh_url
        forge = Forge.send(:from_remote_url, "git@gitlab.com:user/repo.git")
        assert_instance_of(Gitlab, forge)
      end

      def test_detect_gitlab_self_hosted
        forge = Forge.send(:from_remote_url, "https://gitlab.company.com/team/repo.git")
        assert_instance_of(Gitlab, forge)
      end

      def test_detect_unknown_returns_nil
        forge = Forge.send(:from_remote_url, "https://bitbucket.org/user/repo.git")
        assert_nil(forge)
      end

      def test_detect_github_repo_with_gitlab_in_path
        forge = Forge.send(:from_remote_url, "https://github.com/gitlab-org/repo.git")
        assert_instance_of(Github, forge)
      end

      def test_detect_gitlab_ssh_self_hosted
        forge = Forge.send(:from_remote_url, "git@gitlab.company.com:team/repo.git")
        assert_instance_of(Gitlab, forge)
      end

      def test_detect_config_override_github
        with_test_repository("a-b") do
          Git.exec("config", "--local", "chain.forge", "github")
          forge = Forge.detect(remote_url: "https://gitlab.com/user/repo.git")
          assert_instance_of(Github, forge)
        end
      end

      def test_detect_config_override_gitlab
        with_test_repository("a-b") do
          Git.exec("config", "--local", "chain.forge", "gitlab")
          forge = Forge.detect(remote_url: "https://github.com/user/repo.git")
          assert_instance_of(Gitlab, forge)
        end
      end
    end
  end
end
