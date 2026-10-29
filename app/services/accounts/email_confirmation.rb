# frozen_string_literal: true

module Accounts
  # Confirming an address from the page its link opens, with the password in
  # use. The link shows the mailbox is the person's, and the password that
  # whoever holds the session is: an address someone else typed, such as the
  # one an inviter gave, becomes where links to set a password go only by
  # the person's own hand (Profiles::ConfirmEmail).
  #
  #   confirmation = Accounts::EmailConfirmation.new(current_profile, params.expect(email_confirmation: [ :token, :current_password ]))
  #   confirmation.problem   # why the link can't confirm (Profiles::ConfirmEmail.problem), nil when it can
  #   confirmation.save      # false: confirmation.problem or confirmation.errors says why
  class EmailConfirmation
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :token, :string
    attribute :current_password, :string

    validates :current_password, presence: true

    attr_reader :problem

    def initialize(profile, values = {})
      @profile = profile
      super(values)
      @problem = Profiles::ConfirmEmail.problem(profile, token: token)
    end

    # The address the link confirms.
    def address = @profile.address_to_confirm

    # A link that can't confirm anything asks for no password.
    def save
      return false if problem || invalid?
      return refused(:current_password, :invalid) unless @profile.try_password(current_password)

      result = Profiles::ConfirmEmail.call(@profile, token: token)
      @problem = result.error
      result.success?
    end

    private

    def refused(attribute, error)
      errors.add(attribute, error)
      false
    end
  end
end
