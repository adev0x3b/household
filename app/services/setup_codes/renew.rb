# frozen_string_literal: true

# A new setup code for a copy nobody has signed in to yet, replacing any
# code before it: the one printed when the copy was installed is lost, or a
# development server makes its own. Refused once anyone exists, since the
# setup page is gone from then on.
#
#   result = SetupCodes::Renew.call
#   result.code      # "K7QM-2XRD-9VWP-HC4T", to show once; nil when refused
#   result.error     # :already_set_up
module SetupCodes
  class Renew
    Result = ServiceResult.define(:code)

    def self.call
      code = SetupCode.generate
      made = Platform::Setting.transaction do
        # The lock the first account is made under, so a code is never made
        # just after it, when nobody could use it any more.
        Platform::Setting.connection.execute("SELECT pg_advisory_xact_lock(#{Admins::Create::FIRST_ACCOUNT_LOCK})")
        next false if Profile.exists?

        Platform::Setting.first_or_start.update!(setup_code_digest: SetupCode.digest(code))
      end
      made ? Result.new(code: code, error: nil) : Result.new(code: nil, error: :already_set_up)
    end
  end
end
