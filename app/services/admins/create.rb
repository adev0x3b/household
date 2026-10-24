# frozen_string_literal: true

# The first account on a fresh database: a household and its admin — the
# admin, who then creates the other households (/admin/households) and
# holds the app's settings. From the setup page (SetupController) or
# `bin/rails admin:create`. Both are saved or neither: the profile comes
# back with every error, the household's included (on base).
#
#   result = Admins::Create.call(household_name: "Casa", username: "alex", email: "alex@example.com",
#                                   password: "…", password_confirmation: "…", first: true)
#   result.success?   # false (error :invalid): result.profile.errors says what was wrong
#
# `first: true` (the setup page): only while nobody exists, decided under a
# database lock, so two submissions of a fresh setup page can't both make
# the first admin. The rake tasks make one on a database that has people.
module Admins
  class Create
    # Taken by `first: true` around "is anyone here?" and the save.
    FIRST_ACCOUNT_LOCK = 0x486f7573 # "Hous"

    Result = ServiceResult.define(:profile)

    def self.call(...)
      profile = build(...)
      Result.new(profile: profile, error: (:invalid unless profile.persisted?))
    end

    # The profile, saved with its household, or with every reason it wasn't.
    # The first setup also names the person and picks their language and the
    # household's currency; the rake tasks leave the defaults.
    def self.build(household_name:, username:, email:, password:, password_confirmation: password, first: false,
                   first_name: nil, last_name: nil, locale: nil, currency: nil)
      household = Household.new(name: household_name)
      household.currency = currency if currency.present?
      profile = Profile.new(household: household, username: username, email: email, password: password,
                            password_confirmation: password_confirmation, role: :admin,
                            first_name: first_name.presence, last_name: last_name.presence)
      profile.locale = locale if locale.present?

      # Everything wrong at once, from both, the household's under its own
      # name so the page can mark its field.
      profile.valid?
      household.errors.each { |error| profile.errors.import(error, attribute: "household.#{error.attribute}") } unless household.valid?
      return profile if profile.errors.any?

      Household.transaction do
        if first
          Household.connection.execute("SELECT pg_advisory_xact_lock(#{FIRST_ACCOUNT_LOCK})")
          next profile.errors.add(:base, :already_set_up) unless Profile.none?
        end

        household.save!
        profile.save!
        Profiles::Join.call(profile)
        household.update!(owner: profile)
        forget_the_setup_code
      end
      profile
    rescue ActiveRecord::RecordInvalid => e
      # A race with another first account, or a rule the validations above don't cover.
      e.record.errors.full_messages.each { |message| profile.errors.add(:base, message) } unless e.record.equal?(profile)
      profile
    end
    private_class_method :build

    # The setup code opens the page only until someone exists: left behind, it
    # would open it again on a database emptied later.
    def self.forget_the_setup_code
      setting = Platform::Setting.first
      setting.update!(setup_code_digest: nil) if setting&.setup_code_digest.present?
    end
    private_class_method :forget_the_setup_code
  end
end
