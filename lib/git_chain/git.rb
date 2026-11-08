# frozen_string_literal: true

require "open3"

module GitChain
  class Git
    class Failure < StandardError
      def initialize(args, err)
        super("git #{args.join(" ")} failed: \n#{err}")
      end
    end

    class << self
      def capture3(*args, dir: nil)
        cmd = ["git"]
        cmd += ["-C", dir] if dir
        cmd += args
        Open3.capture3(*cmd)
      end

      def exec(*args, dir: nil)
        out, err, stat = capture3(*args, dir: dir)
        raise(Failure.new(args, err)) unless stat.success?

        out.chomp
      end

      def branches(dir: nil)
        exec("branch", "--list", "--format=%(refname:short)", dir: dir).split
      rescue Failure
        []
      end

      def chains(chain_name: nil, dir: nil)
        args = ["config", "--null", "--get-regexp", '^branch\\..+\\.chain$']
        args << "^#{Regexp.escape(chain_name)}$" if chain_name
        exec(*args, dir: dir)
          .split("\0")
          .map { |out| out.split("\n") }
          .map { |lines| [parse_branch_name(lines.shift), *lines] }
          .to_h
      rescue Failure
        {}
      end

      def current_branch(dir: nil)
        exec("symbolic-ref", "--short", "HEAD", dir: dir)
      rescue Failure
        nil
      end

      # 'origin/foo/bar'
      def upstream_branch(branch: "", dir: nil)
        exec("rev-parse", "--abbrev-ref", "--symbolic-full-name", "#{branch}@{u}", dir: dir)
      rescue Failure
        nil
      end

      # 'origin/foo/bar'
      def push_branch(branch: "", dir: nil)
        exec("rev-parse", "--abbrev-ref", "--symbolic-full-name", "#{branch}@{push}", dir: dir)
      rescue Failure
        nil
      end

      def remote_name(branch: "", dir: nil)
        upstream_branch(branch: branch, dir: dir)&.split("/", 2)&.first
      end

      def remote_url(branch: "", dir: nil)
        name = remote_name(branch: branch, dir: dir)
        return if name.to_s.empty?

        exec("remote", "get-url", name)
      end

      def ancestor?(ancestor:, rev:, dir: nil)
        _, _, stat = capture3("merge-base", "--is-ancestor", ancestor, rev, dir: dir)
        stat.success?
      end

      def merge_base(commit, *commits, dir: nil)
        exec("merge-base", commit, *commits, dir: dir)
      rescue
        nil
      end

      def rev_parse(rev, dir: nil)
        exec("rev-parse", rev, dir: dir)
      rescue Failure
        nil
      end

      def set_config(key, value, scope: nil, dir: nil)
        git_config("--unset-all", key, scope: scope, dir: dir)

        Array(value).each do |val|
          git_config("--add", key, val, scope: scope, dir: dir)
        end
      end

      def get_config(key, urlmatch: nil, scope: nil, dir: nil)
        args = ["--includes"]
        args += if urlmatch
          ["--get-urlmatch", key, urlmatch]
        else
          ["--get", key]
        end
        out, _, stat = git_config(*args, scope: scope, dir: dir)
        return unless stat.success?

        out = out.chomp
        out unless out.empty?
      end

      def get_all_configs(key, scope: nil, dir: nil)
        current_vals, _, stat = git_config("--includes", "--get-all", key, scope: scope, dir: dir)
        return [] unless stat.success?

        current_vals.lines.map(&:strip)
      end

      def ahead_behind(branch, upstream, dir: nil)
        out = exec("rev-list", "--left-right", "--count", "#{upstream}...#{branch}", dir: dir)
        behind, ahead = out.split("\t").map(&:to_i)
        { ahead: ahead, behind: behind }
      rescue Failure
        nil
      end

      def rebase_in_progress?(dir: nil)
        dir ||= ".git"
        !Dir.glob(File.join(File.expand_path(dir), "rebase-{apply,merge}")).empty?
      end

      def git_version
        @git_version ||= exec("version")[/^git version (\S+)/, 1]
      rescue Failure
        nil
      end

      def supports_update_refs?
        version = git_version
        return false unless version

        version_at_least?(version, "2.38.0")
      end

      def reset_version_cache
        @git_version = nil
      end

      # Branches checked out in worktrees other than the current one.
      # Git refuses to move these refs during a rebase with --update-refs.
      # Returns nil when the worktree list cannot be read, so callers treat
      # the result as unknown rather than empty.
      def other_worktree_branches(dir: nil)
        out = exec("worktree", "list", "--porcelain", dir: dir)
        toplevel = exec("rev-parse", "--show-toplevel", dir: dir)
        current = File.expand_path(toplevel)

        out.split("\n\n").map do |block|
          lines = block.split("\n")
          path = lines.shift[/^worktree (.+)$/, 1]
          next if path.nil? || File.expand_path(path) == current

          lines.find { |line| line.start_with?("branch ") }&.delete_prefix("branch ")
        end.compact
      rescue Failure
        nil
      end

      # Local branch refs as { "refs/heads/<name>" => sha }. Returns nil when
      # refs cannot be enumerated, so callers treat the result as unknown.
      def branch_refs(dir: nil)
        exec("for-each-ref", "--format=%(refname) %(objectname)", "refs/heads", dir: dir)
          .split("\n")
          .map { |line| line.split(" ") }
          .to_h
      rescue Failure
        nil
      end

      private

      def version_at_least?(version, minimum)
        parts = version.split(".").map(&:to_i)
        min_parts = minimum.split(".").map(&:to_i)

        [parts.size, min_parts.size].max.times do |i|
          a = parts[i] || 0
          b = min_parts[i] || 0
          return a > b if a != b
        end

        true
      end

      def git_config(*config_args, scope: nil, dir: nil)
        args = ["config"]

        case scope
        when nil
        when :local, :global
          args << "--#{scope}"
        else
          raise "Invalid git scope: #{scope}"
        end
        args += config_args
        capture3(*args, dir: dir)
      end

      def parse_branch_name(config)
        match = /^branch\.(.+)\.[a-zA-Z]+$/.match(config)
        raise("Expected config #{config} to match regexp") unless match

        match[1]
      end
    end
  end
end
