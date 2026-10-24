# frozen_string_literal: true

module Assistant
  module ChangeSets
    class Undoer
      # A share the set made goes, unless it went meanwhile.
      class Shared < Step
        private

        def revert(share) = share.destroy!
      end
    end
  end
end
