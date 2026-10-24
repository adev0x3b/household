# frozen_string_literal: true

# bin/provision's parts (lib/provision/): the list of a destination's
# settings first, shared with the tests that hold config/deploy*.yml and the
# Deploy workflow to it. Rails autoloads them; the script, which runs
# without Rails, requires each file it needs.
module Provision
end
