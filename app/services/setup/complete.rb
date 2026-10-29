# frozen_string_literal: true

module Setup
  # Saves the first setup (Setup::Form) at once: the household and its
  # admin (Admins::Create), what the installation allows, the bookshelf's
  # sources and the mail it sends (Platform::Setting), the assistant's model
  # (Assistant::Setting) and the housemates' invitations. All of it or
  # none: the steps then carry what was wrong.
  #
  #   result = Setup::Complete.call(form)
  #   result.success?      # false (error :invalid): the form's steps say why
  #   result.profile       # the admin, to sign in
  #   result.invitations   # [Households::Invite::Result], each link readable only now
  class Complete
    Result = ServiceResult.define(:profile, :invitations)

    def self.call(form) = new(form).call

    def initialize(form)
      @form = form
    end

    def call
      return failed unless @form.valid?

      ActiveRecord::Base.transaction do
        profile = admin
        raise ActiveRecord::Rollback unless profile

        settings_by(profile)
        invitations = invite(profile)
        raise ActiveRecord::Rollback unless invitations

        return Result.new(profile:, invitations:, error: nil)
      end
      failed
    end

    private

    def step(kind) = @form.step(kind)

    # A refusal here (someone else set the copy up a moment ago) is the
    # account step's to show.
    def admin
      household = step(Setup::HouseholdDetails)
      result = Admins::Create.call(household_name: household.name, currency: household.currency, first: true,
                                   **step(Setup::Account).to_admin)
      return result.profile if result.success?

      result.profile.errors.each { |error| step(Setup::Account).errors.import(error) }
      nil
    end

    def settings_by(profile)
      setting = Platform::Setting.first_or_start
      step(Installation::Allowances).apply_to(setting)
      step(Installation::Books).apply_to(setting)
      step(Installation::Mail).apply_to(setting)
      setting.updated_by = profile
      setting.save!

      assistant = step(Installation::Assistant)
      return unless assistant.asked?(@form)

      assistant.setting.updated_by = profile
      assistant.setting.save!
    end

    # Each invitation is checked as any member's is; one refused undoes the
    # setup, with the reason on its row.
    def invite(profile)
      housemates = step(Setup::Housemates)
      results = housemates.people.map do |person|
        Households::Invite.call(profile.household, inviter: profile, email: person.email, first_name: person.first_name)
      end
      refused = results.reject(&:success?)
      refused.each { |result| result.profile.errors.full_messages.each { |message| housemates.errors.add(:base, message) } }
      results if refused.none?
    end

    def failed = Result.new(profile: nil, invitations: [], error: :invalid)
  end
end
