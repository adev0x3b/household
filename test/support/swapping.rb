# frozen_string_literal: true

# The suite's one way to stand in for a method: there is no mocking library,
# so a test that must keep a call from going out (to a model, to GitHub, to
# a book catalogue) swaps the method on that one object for the block and
# gets exactly what was there back afterwards.
module Swapping
  # Replaces `object`'s singleton method for the block, then puts back what
  # was there: the object's own method with its visibility, or nothing, so
  # the one it inherits answers again.
  def swapping(object, method_name, replacement)
    singleton = object.singleton_class
    own = singleton.method_defined?(method_name, false) || singleton.private_method_defined?(method_name, false)
    original = singleton.instance_method(method_name) if own
    hidden = own && singleton.private_method_defined?(method_name, false)
    object.define_singleton_method(method_name, &replacement)
    begin
      yield
    ensure
      if own
        singleton.define_method(method_name, original)
        singleton.class_eval { private method_name } if hidden
      else
        singleton.remove_method(method_name)
      end
    end
  end
end
