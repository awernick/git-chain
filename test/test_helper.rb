# frozen_string_literal: true

require File.expand_path("../../vendor/bootstrap.rb", __FILE__)
require "git_chain"

require "minitest"
require "mocha/minitest"
require "minitest/autorun"
require "minitest/reporters"

Minitest::Reporters.use!
CLI::UI.enable_color = true

require "tmpdir"
require "fileutils"
require "tempfile"
require "open3"

module RepositoryTestHelper
  def with_test_repository(fixture_name = "a-b")
    previous_dir = Dir.pwd
    setup_script = File.expand_path("../../fixtures/#{fixture_name}.sh", __FILE__)

    Dir.mktmpdir("git-chain-rebase") do |dir|
      Dir.chdir(dir)
      _, err, stat = Open3.capture3(setup_script)
      raise "Cannot setup git repository using #{setup_script}: #{err}" unless stat.success?

      yield
    ensure
      Dir.chdir(previous_dir) if previous_dir
    end
  end
end

module Minitest
  class Test
    def capture_io(&block)
      cap = CLI::UI::StdoutRouter::Capture.new(with_frame_inset: true, &block)
      cap.run
      [cap.stdout, cap.stderr]
    end

    # Records the arguments of every `git rebase` invocation made through
    # GitChain::Git.exec while delegating all calls to the real
    # implementation. Yields the recorded calls.
    def with_rebase_recording
      calls = []
      singleton = ::GitChain::Git.singleton_class
      singleton.send(:alias_method, :exec_without_rebase_recording, :exec)
      singleton.send(:define_method, :exec) do |*args, **kwargs|
        calls << args.dup if args.first == "rebase"
        exec_without_rebase_recording(*args, **kwargs)
      end
      yield calls
    ensure
      singleton = ::GitChain::Git.singleton_class
      singleton.send(:alias_method, :exec, :exec_without_rebase_recording)
      singleton.send(:remove_method, :exec_without_rebase_recording)
    end
  end
end
