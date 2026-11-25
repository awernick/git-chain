# frozen_string_literal: true

require "test_helper"

module GitChain
  module Commands
    class CommandTest < Minitest::Test
      def test_help_prints_usage
        out, _err = capture_io do
          assert_raises(SystemExit) do
            Setup.new.call(["--help"])
          end
        end

        plain = out.gsub(/\e\[[\d;]*m/, "")

        assert_includes(plain, "Usage: git chain setup")
        assert_includes(plain, "--chain=NAME")
      end
    end
  end
end
