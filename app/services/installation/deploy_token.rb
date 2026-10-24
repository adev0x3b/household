# frozen_string_literal: true

module Installation
  # The GitHub token behind /admin/deployment's buttons, as a card on
  # /admin/settings. A secret: never shown back, and a blank field keeps the
  # saved one.
  class DeployToken
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :deploy_dispatch_token, :string

    def self.param_key = :deploy_token

    def self.current = new

    def assign(values)
      self.deploy_dispatch_token = values.to_h.symbolize_keys[:deploy_dispatch_token].to_s.strip.presence
      self
    end

    def apply_to(setting)
      setting.deploy_dispatch_token = deploy_dispatch_token if deploy_dispatch_token.present?
      setting
    end
  end
end
