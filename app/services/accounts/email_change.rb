# frozen_string_literal: true

module Accounts
  # Asking for another address on the Account page, with the password in
  # use. Where mail goes out, the new address waits for the link mailed to
  # it (Profiles::ConfirmEmail) and the confirmed one hears of it first;
  # where none does, it takes over at once, unconfirmed. Either way nothing
  # is mailed to it before it is confirmed but that link.
  #
  #   change = Accounts::EmailChange.new(current_profile, params.expect(email_change: [ :email, :current_password ]))
  #   change.save   # false: change.errors says why
  class EmailChange
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :email, :string
    attribute :current_password, :string

    validates :email, presence: true
    validates :email, format: { with: Devise.email_regexp }, allow_blank: true
    validates :current_password, presence: true
    validate :another_address

    def initialize(profile, values = {})
      @profile = profile
      super(values)
    end

    def email=(value)
      super(value.to_s.strip.downcase.presence)
    end

    # The password comes before anything that reads other accounts, so
    # whether an address is in use is told only to whoever knows it.
    def save
      return false if invalid?
      return refused(:current_password, :invalid) unless @profile.try_password(current_password)
      return refused(:email, :taken) if Profile.where.not(id: @profile.id).exists?(email: email)

      Emails.enabled? ? wait_for_the_link : change_at_once
    end

    private

    # Under the household's lock, so two requests at once can't both take the
    # last link of the day.
    def wait_for_the_link
      @profile.household.with_lock do
        next refused(:base, :no_links_left, count: Emails::ConfirmationAllowance::PER_DAY) unless Emails::ConfirmationAllowance.new(@profile).any_left?

        confirmed = @profile.email if @profile.email_confirmed?
        @profile.update!(unconfirmed_email: email)
        Emails::Enqueue.call(@profile, :email_confirmation)
        Emails::Enqueue.call(@profile, :email_change_requested, data: { "to" => confirmed }) if confirmed
        true
      end
    end

    def change_at_once
      @profile.update!(email: email, unconfirmed_email: nil)
      true
    end

    def another_address
      errors.add(:email, :same) if email.present? && email == @profile.email
    end

    def refused(attribute, error, **options)
      errors.add(attribute, error, **options)
      false
    end
  end
end
