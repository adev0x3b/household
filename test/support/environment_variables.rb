# frozen_string_literal: true

# Tests reach into the environment often: Platform reads the installation's
# limits from it, the assistant and the deployment console their
# configuration, and .env fills it on a development machine. These are the
# two ways to change it, and both put back what the process had.
module EnvironmentVariables
  extend ActiveSupport::Concern

  class_methods do
    # Every test of the case starts with these variables unset and sets what
    # it needs; what the process had comes back after each one.
    def isolate_env(*names)
      before = nil
      setup do
        before = ENV.to_h.slice(*names)
        names.each { ENV.delete(_1) }
      end
      teardown { restore_env(before, names) }
    end
  end

  # The environment as given for the block, then as it was: a value nil
  # removes the variable.
  def with_env(values)
    before = ENV.to_h.slice(*values.keys)
    values.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    yield
  ensure
    restore_env(before, values.keys)
  end

  private

  def restore_env(before, names)
    names.each { |name| before.key?(name) ? ENV[name] = before[name] : ENV.delete(name) }
  end
end
