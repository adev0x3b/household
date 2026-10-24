# frozen_string_literal: true

module RuboCop
  module Cop
    module Household
      # A component is the kit every area shares, so it never names a view:
      # a piece that draws one area's card, badge or row is that area's view,
      # under app/views/<area>/. A view may draw any component, and another
      # area's view, but not the other way round.
      #
      # @example
      #   # bad, in app/components
      #   render Views::Tasks::PriorityBadge.new(priority: priority)
      #
      #   # good
      #   render Components::StatusBadge.new(tone: :warning, icon: "fa-flag", label: label)
      class ComponentNamesNoView < Base
        MSG = "A component never names a view (`%<name>s`): a piece that draws one area's view belongs in that area's app/views."

        def on_const(node)
          return unless node.short_name == :Views && (node.namespace.nil? || node.namespace.cbase_type?)

          name = node
          name = name.parent while name.parent&.const_type? && name.parent.namespace.equal?(name)
          add_offense(name, message: format(MSG, name: name.source))
        end
      end
    end
  end
end
