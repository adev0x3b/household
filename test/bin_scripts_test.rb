# frozen_string_literal: true

require "test_helper"

# Scripts in bin/ run straight from a checkout — on CI, on the server, by
# hand — so git must record them as executable, wherever they were written
# (a machine with core.fileMode off doesn't notice a missing bit).
class BinScriptsTest < ActiveSupport::TestCase
  test "every script in bin/ is executable in git" do
    modes = IO.popen([ "git", "ls-files", "-s", "--", "bin" ], chdir: Rails.root, &:read).lines.to_h do |line|
      mode, _object, _stage, path = line.split(/\s+/, 4)
      [ path.strip, mode ]
    end

    assert_not_empty modes
    assert_empty modes.reject { |_, mode| mode == "100755" }.keys, "make them executable: git update-index --chmod=+x <script>"
  end
end
