# frozen_string_literal: true

require "test_helper"

module GitChain
  class AnsiTest < Minitest::Test
    def test_hyperlink_generates_osc8_sequence
      url = "https://github.com/user/repo/pull/42"
      text = "#42"
      result = CLI::UI::ANSI.hyperlink(url, text)

      expected = "\x1b]8;;#{url}\x1b\\#{text}\x1b]8;;\x1b\\"
      assert_equal(expected, result)
    end

    def test_strip_codes_removes_osc8_sequences
      url = "https://github.com/user/repo/pull/42"
      text = "#42"
      hyperlinked = CLI::UI::ANSI.hyperlink(url, text)

      stripped = CLI::UI::ANSI.strip_codes(hyperlinked)
      assert_equal(text, stripped)
    end

    def test_printing_width_ignores_osc8_sequences
      url = "https://github.com/user/repo/pull/42"
      text = "#42"
      hyperlinked = CLI::UI::ANSI.hyperlink(url, text)

      assert_equal(3, CLI::UI::ANSI.printing_width(hyperlinked))
    end

    def test_strip_codes_still_removes_sgr_codes
      sgr_text = "\x1b[31mred text\x1b[0m"
      stripped = CLI::UI::ANSI.strip_codes(sgr_text)

      assert_equal("red text", stripped)
    end

    def test_strip_codes_removes_mixed_osc8_and_sgr
      url = "https://example.com"
      hyperlinked = "\x1b[36m" + CLI::UI::ANSI.hyperlink(url, "#1") + "\x1b[0m"

      stripped = CLI::UI::ANSI.strip_codes(hyperlinked)
      assert_equal("#1", stripped)
    end
  end
end
