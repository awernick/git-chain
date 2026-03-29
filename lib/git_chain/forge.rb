# frozen_string_literal: true

require "open3"

module GitChain
  module Forge
    autoload :Base, "git_chain/forge/base"
    autoload :Github, "git_chain/forge/github"
    autoload :Gitlab, "git_chain/forge/gitlab"

    class << self
      # Detect the forge from git config override or remote URL.
      # Returns a forge adapter instance, or nil if detection fails.
      def detect(remote_url: nil)
        cli_override = Git.get_config("chain.forgeCli")

        adapter = from_config_override(cli_override)
        return adapter if adapter

        remote_url ||= Git.remote_url(branch: Git.current_branch.to_s)
        return if remote_url.nil? || remote_url.empty?

        from_remote_url(remote_url, cli_override)
      end

      # Detect the forge and verify CLI availability.
      # Raises Abort with a clear message on failure.
      def detect!(remote_url: nil)
        forge = detect(remote_url: remote_url)

        unless forge
          raise(Abort, "No forge detected. Ensure the remote points to GitHub or GitLab, " \
            "or set forge manually: git config chain.forge github")
        end

        unless forge.cli_available?
          raise(Abort, "Forge CLI '#{forge.cli_command}' is not available. " \
            "Install it or override: git config chain.forgeCli /path/to/cli")
        end

        forge
      end

      private

      def from_config_override(cli_override)
        forge_type = Git.get_config("chain.forge")
        return unless forge_type

        case forge_type.downcase
        when "github" then Github.new(cli_command: cli_override)
        when "gitlab" then Gitlab.new(cli_command: cli_override)
        end
      end

      def from_remote_url(url, cli_override)
        host = extract_host(url)
        return unless host

        case host
        when /\Agithub\.com\z/ then Github.new(cli_command: cli_override)
        when /gitlab/ then Gitlab.new(cli_command: cli_override)
        end
      end

      # Extract the hostname from an SSH or HTTPS git remote URL.
      # Handles:
      #   https://github.com/user/repo.git
      #   git@github.com:user/repo.git
      #   ssh://git@github.com/user/repo.git
      def extract_host(url)
        if (match = url.match(%r{\A(?:https?|git)://([^/:]+)}))
          match[1]
        elsif (match = url.match(/\A[^@]+@([^:]+):/))
          match[1]
        end
      end
    end
  end
end
