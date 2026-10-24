# frozen_string_literal: true

# Rails' exceptions app: the page from public/ for a request that failed,
# in its reader's language. It reads only the request, never the database,
# which may be what failed, and it runs whether or not a controller did (a
# wrong address reaches no controller). So the language is the one the
# person's last page was in, which ApplicationController keeps in their
# session, else the browser's.
class ErrorPages
  SESSION_KEY = "locale"

  def initialize(public_path)
    @pages = ActionDispatch::PublicExceptions.new(public_path)
  end

  def call(env)
    I18n.with_locale(locale(env)) { @pages.call(env) }
  end

  private

  def locale(env)
    remembered = env["rack.session"]&.[](SESSION_KEY)
    return remembered.to_sym if remembered.present? && I18n.locale_available?(remembered)

    AcceptLanguage.new(env["HTTP_ACCEPT_LANGUAGE"]).locale || I18n.default_locale
  end
end
