# frozen_string_literal: true

# bin/release's parts (lib/releases/): what a promotion to production
# publishes for the people who run a copy of their own. Rails autoloads
# them; the script, which runs without Rails, requires each file it needs.
module Releases
  # Anything that keeps a release from being prepared: git refusing, a
  # malformed argument.
  class Error < StandardError; end
end
