# frozen_string_literal: true

# Setting a new password from a link made on the household page
# (Profiles::PasswordLink). Nothing asks for one by email: the routes keep
# only these two actions.
class Profiles::PasswordsController < Devise::PasswordsController
  # A link's token can't be guessed; trying anyway is slowed like signing in.
  rate_limit to: 10, within: 3.minutes, only: :update, with: -> { rate_limited }

  # GET /profiles/password/edit?reset_password_token=...
  def edit
    super
    render form
  end

  # PUT /profiles/password
  def update
    super do |profile|
      next if profile.errors.empty?

      return render form, status: :unprocessable_content
    end
  end

  protected

  # A password set from a link opens an account locked by wrong passwords:
  # whoever made the link vouched for the person (Devise only does this when
  # unlocking goes by email, which it doesn't here).
  def unlockable?(resource) = resource.respond_to?(:unlock_access!)

  private

  def form = Views::Devise::Passwords::Edit.new(resource: resource, resource_name: resource_name)
end
