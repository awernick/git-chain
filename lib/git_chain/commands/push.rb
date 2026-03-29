# frozen_string_literal: true
require "optparse"

module GitChain
  module Commands
    class Push < Command
      include Options::ChainName

      def description
        "Push all branches of the chain to upstream"
      end

      def default_options
        { force_mode: :force_with_lease }
      end

      def configure_option_parser(opts, options)
        super

        opts.on("-u", "--set-upstream", "Set upstream to matching names, if not already set") do
          options[:set_upstream] = true
        end

        opts.on("-f", "--force", "Use hard force push (may overwrite remote changes)") do
          options[:force_mode] = :force
        end

        opts.on("--no-force", "Use regular push (fails on diverged history)") do
          options[:force_mode] = :no_force
        end

        opts.on("-n", "--dry-run", "Show what would be pushed without pushing") do
          options[:dry_run] = true
        end
      end

      def run(options)
        chain = current_chain(options)
        remote = nil
        upstreams = {}

        chain.branch_names[1..-1].each do |b|
          upstream = Git.push_branch(branch: b)
          if upstream
            branch_remote, upstream_branch = upstream.split("/", 2)
            if remote && branch_remote != remote
              raise(Abort, "Multiple remotes detected: #{remote}, #{branch_remote}")
            else
              remote = branch_remote
            end
            upstreams[b] = upstream_branch
          elsif options[:set_upstream]
            upstreams[b] = b
          end
        end

        raise(Abort, "Nothing to push") if upstreams.empty?

        remote ||= Git.exec("remote").split("\n").first
        raise(Abort, "No remote configured") unless remote

        if options[:dry_run]
          dry_run(remote, upstreams, options[:force_mode])
        else
          push_branches(remote, upstreams, options)
        end
      end

      private

      def dry_run(remote, upstreams, force_mode)
        mode_label = case force_mode
        when :force then "--force"
        when :force_with_lease then "--force-with-lease"
        when :no_force then "no force"
        end

        puts_info("Dry run: would push to {{info:#{remote}}} with #{mode_label}")

        upstreams.each do |local, upstream|
          status = branch_push_status(remote, local, upstream)
          case status
          when :up_to_date
            puts_skip("#{local} → #{remote}/#{upstream} (up-to-date)")
          when :fast_forward
            puts_info("#{local} → #{remote}/#{upstream} (ahead)")
          when :behind
            puts_warning("#{local} → #{remote}/#{upstream} (behind remote)")
          when :diverged
            puts_warning("#{local} → #{remote}/#{upstream} (diverged, force push needed)")
          when :new_branch
            puts_info("#{local} → #{remote}/#{upstream} (new branch)")
          end
        end
      end

      def push_branches(remote, upstreams, options)
        force_mode = options[:force_mode]
        if force_mode == :force
          puts_warning("Using hard force push. This may overwrite remote changes.")
        end

        results = []
        upstreams.each do |local, upstream|
          status = branch_push_status(remote, local, upstream)
          if status == :up_to_date
            puts_skip("#{local} → #{remote}/#{upstream} (up-to-date)")
            results << { branch: local, status: :up_to_date }
            next
          end

          if status == :behind
            puts_warning("#{local} is behind #{remote}/#{upstream}, consider rebasing first")
          end

          cmd = ["push"]
          case force_mode
          when :force
            cmd << "--force"
          when :force_with_lease
            cmd << "--force-with-lease"
          end
          cmd += [remote, "#{local}:#{upstream}"]

          puts_debug(["git", *cmd].join(" "))
          _, stderr, exit_status = Git.capture3(*cmd)

          if exit_status.success?
            puts_success("#{local} → #{remote}/#{upstream}")
            results << { branch: local, status: :success }
          else
            puts_error("#{local} → #{remote}/#{upstream} (push failed)")
            puts_debug(stderr.chomp) unless stderr.empty?
            results << { branch: local, status: :failure }
          end
        end

        if options[:set_upstream]
          pushed = results.select { |r| r[:status] != :failure }.map { |r| r[:branch] }
          upstreams.each do |local, upstream|
            next unless pushed.include?(local)

            args = ["branch", "--set-upstream-to=#{remote}/#{upstream}", local]
            puts_debug_git(*args)
            Git.exec(*args)
          end
        end

        report_summary(results)
      end

      def branch_push_status(remote, local, upstream)
        remote_ref = "#{remote}/#{upstream}"
        _, _, status = Git.capture3("rev-parse", "--verify", remote_ref)

        return :new_branch unless status.success?

        local_sha = Git.exec("rev-parse", local)
        remote_sha = Git.exec("rev-parse", remote_ref)

        return :up_to_date if local_sha == remote_sha

        _, _, ff_status = Git.capture3("merge-base", "--is-ancestor", remote_ref, local)
        return :fast_forward if ff_status.success?

        _, _, behind_status = Git.capture3("merge-base", "--is-ancestor", local, remote_ref)
        behind_status.success? ? :behind : :diverged
      end

      def report_summary(results)
        succeeded = results.count { |r| r[:status] == :success }
        up_to_date = results.count { |r| r[:status] == :up_to_date }
        failed = results.count { |r| r[:status] == :failure }

        parts = []
        parts << "#{succeeded} pushed" if succeeded > 0
        parts << "#{up_to_date} up-to-date" if up_to_date > 0
        parts << "#{failed} failed" if failed > 0

        puts_info("Push complete: #{parts.join(", ")}")

        return unless failed > 0

        failed_branches = results.select { |r| r[:status] == :failure }.map { |r| r[:branch] }
        raise(Abort, "Failed to push: #{failed_branches.join(", ")}")
      end
    end
  end
end
