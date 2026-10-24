# frozen_string_literal: true

module Assistant
  module ChangeSets
    class Undoer
      # A share the set removed comes back.
      class Unshared < Step
        def undo! = entry["model"].constantize.create!(entry["attributes"])
      end
    end
  end
end
