# frozen_string_literal: true

# Re-authentication before the admin's widest powers (GitHub's "sudo
# mode"): changing production, and acting on someone else's account. The
# admin types their password once, inside the action's own modal, and
# it holds for FOR in their session. A stolen session alone can't deploy,
# nor take over or remove anyone, nor guess its way there: a wrong
# password here counts as a wrong sign-in (Profile#try_password), and the
# account locked after ten signs that session out.
#
#   sudo = Admin::Sudo.new(session, current_profile)
#   sudo.active?            # still within the window?
#   sudo.verify(password)   # the right password starts the window; a wrong one is false
#   sudo.passed?(password)  # nothing to ask (a member, or the window is open), or the right password
class Admin::Sudo
  FOR = 15.minutes

  def initialize(session, profile)
    @session = session
    @profile = profile
  end

  def active? = @session[:sudo_until].to_i > Time.current.to_i

  # Only the admin's role is worth a stolen session: a member doing the
  # same to their own household (an owner's password link) is not asked.
  def required? = @profile.admin? && !active?

  def passed?(password) = !required? || verify(password)

  def verify(password)
    return false unless @profile.try_password(password)

    @session[:sudo_until] = FOR.from_now.to_i
    true
  end
end
