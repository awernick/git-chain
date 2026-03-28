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
        adapter = from_config_override
        return adapter if adapter

        remote_url ||= Git.remote_url(branch: Git.current_branch.to_s)
        return nil if remote_url.nil? || remote_url.empty?

        from_remote_url(remote_url)
      end

      private

      def from_config_override
        forge_type = Git.get_config("chain.forge")
        return nil unless forge_type

        case forge_type.downcase
        when "github" then Github.new
        when "gitlab" then Gitlab.new
        end
      end

      def from_remote_url(url)
        host = extract_host(url)
        return nil unless host

        case host
        when /\Agithub\.com\z/ then Github.new
        when /gitlab/ then Gitlab.new
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
