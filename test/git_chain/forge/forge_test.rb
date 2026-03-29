# frozen_string_literal: true

require "test_helper"

module GitChain
  module Forge
    class ForgeTest < Minitest::Test
      include RepositoryTestHelper

      def test_detect_github_from_https_url
        forge = Forge.send(:from_remote_url, "https://github.com/user/repo.git", nil)
        assert_instance_of(Github, forge)
      end

      def test_detect_github_from_ssh_url
        forge = Forge.send(:from_remote_url, "git@github.com:user/repo.git", nil)
        assert_instance_of(Github, forge)
      end

      def test_detect_gitlab_from_https_url
        forge = Forge.send(:from_remote_url, "https://gitlab.com/user/repo.git", nil)
        assert_instance_of(Gitlab, forge)
      end

      def test_detect_gitlab_from_ssh_url
        forge = Forge.send(:from_remote_url, "git@gitlab.com:user/repo.git", nil)
        assert_instance_of(Gitlab, forge)
      end

      def test_detect_gitlab_self_hosted
        forge = Forge.send(:from_remote_url, "https://gitlab.company.com/team/repo.git", nil)
        assert_instance_of(Gitlab, forge)
      end

      def test_detect_unknown_returns_nil
        forge = Forge.send(:from_remote_url, "https://bitbucket.org/user/repo.git", nil)
        assert_nil(forge)
      end

      def test_detect_github_repo_with_gitlab_in_path
        forge = Forge.send(:from_remote_url, "https://github.com/gitlab-org/repo.git", nil)
        assert_instance_of(Github, forge)
      end

      def test_detect_gitlab_ssh_self_hosted
        forge = Forge.send(:from_remote_url, "git@gitlab.company.com:team/repo.git", nil)
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

      def test_default_cli_command_github
        forge = Forge.send(:from_remote_url, "https://github.com/user/repo.git", nil)
        assert_equal("gh", forge.cli_command)
      end

      def test_default_cli_command_gitlab
        forge = Forge.send(:from_remote_url, "https://gitlab.com/user/repo.git", nil)
        assert_equal("glab", forge.cli_command)
      end

      def test_forge_cli_override
        with_test_repository("a-b") do
          Git.exec("config", "--local", "chain.forgeCli", "/usr/local/bin/my-gh")
          forge = Forge.detect(remote_url: "https://github.com/user/repo.git")
          assert_instance_of(Github, forge)
          assert_equal("/usr/local/bin/my-gh", forge.cli_command)
        end
      end

      def test_forge_cli_override_with_forge_override
        with_test_repository("a-b") do
          Git.exec("config", "--local", "chain.forge", "gitlab")
          Git.exec("config", "--local", "chain.forgeCli", "/opt/bin/glab-custom")
          forge = Forge.detect(remote_url: "https://github.com/user/repo.git")
          assert_instance_of(Gitlab, forge)
          assert_equal("/opt/bin/glab-custom", forge.cli_command)
        end
      end

      def test_detect_bang_raises_on_no_forge
        with_test_repository("a-b") do
          err = assert_raises(Abort) do
            Forge.detect!(remote_url: "https://bitbucket.org/user/repo.git")
          end

          assert_match(/No forge detected/, err.message)
          assert_match(/git config chain\.forge/, err.message)
        end
      end

      def test_detect_bang_raises_on_missing_cli
        forge = Forge.detect(remote_url: "https://github.com/user/repo.git")
        forge.stubs(:cli_available?).returns(false)
        Forge.stubs(:detect).returns(forge)

        err = assert_raises(Abort) do
          Forge.detect!(remote_url: "https://github.com/user/repo.git")
        end

        assert_match(/not available/, err.message)
        assert_match(/git config chain\.forgeCli/, err.message)
      end

      def test_detect_bang_returns_forge_when_available
        forge = Forge.detect(remote_url: "https://github.com/user/repo.git")
        forge.stubs(:cli_available?).returns(true)
        Forge.stubs(:detect).returns(forge)

        result = Forge.detect!(remote_url: "https://github.com/user/repo.git")
        assert_instance_of(Github, result)
      end
    end
  end
end
