# frozen_string_literal: true

require "test_helper"

# Every setting of the catalogue reaches a destination the Deploy workflow
# deploys: kamal.yml passes the destination's GitHub environment's variables
# and secrets under the same names, and .kamal/secrets-common names each key
# for Kamal. A setting added to the catalogue fails here until both know it.
class Provision::PassthroughTest < ActiveSupport::TestCase
  test "kamal.yml passes every setting from the destination's environment, a variable or a secret" do
    workflow = Rails.root.join(".github/workflows/kamal.yml").read
    Provision::Settings.all.each do |setting|
      source = setting.secret? ? "secrets" : "vars"
      assert_includes workflow, "#{setting.name}: ${{ #{source}.#{setting.name} }}", setting.name
    end
  end

  test ".kamal/secrets-common names every key, and config/deploy.yml passes each only where it is set" do
    secrets = Rails.root.join(".kamal/secrets-common").read
    deploy = Rails.root.join("config/deploy.yml").read
    Provision::Settings.secret.each do |setting|
      assert_includes secrets, "#{setting.name}=${#{setting.name}}", setting.name
      assert_includes deploy, setting.name, setting.name
    end
  end
end
