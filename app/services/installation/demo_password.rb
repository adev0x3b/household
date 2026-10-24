# frozen_string_literal: true

module Installation
  # The password of the demo household's accounts, as a card on
  # /admin/settings. A secret: never shown back, and a blank field keeps the
  # saved one.
  class DemoPassword
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :demo_password, :string

    # The demo's members sign in with it, so Devise's rules apply.
    validates :demo_password, length: { in: Devise.password_length }, allow_nil: true

    def self.param_key = :demo_password

    def self.current = new

    def assign(values)
      self.demo_password = values.to_h.symbolize_keys[:demo_password].to_s.strip.presence
      self
    end

    def apply_to(setting)
      setting.demo_password = demo_password if demo_password.present?
      setting
    end
  end
end
