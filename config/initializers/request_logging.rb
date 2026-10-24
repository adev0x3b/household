# frozen_string_literal: true

# A public file link (/s/:token) is its token, and the database keeps only
# the token's digest, so the log would be the one place a working link could
# be read back. The request line writes the token [FILTERED], and a redirect
# to the link's file is logged as [FILTERED] whole. Query strings need nothing
# here: they are filtered by parameter name (filter_parameter_logging.rb).
module HouseholdApp
  class RequestLogger < Rails::Rack::Logger
    PUBLIC_LINKS = "#{Rails.configuration.x.mount_path}/s/".freeze
    PUBLIC_LINK_TOKEN = %r{\A(#{Regexp.escape(PUBLIC_LINKS)})[^/]+}

    private

    def started_request_message(request)
      return super unless request.path.start_with?(PUBLIC_LINKS)

      super.sub(request.path, request.path.sub(PUBLIC_LINK_TOKEN, '\1[FILTERED]'))
    end
  end
end

Rails.application.configure do
  config.middleware.swap Rails::Rack::Logger, HouseholdApp::RequestLogger, config.log_tags
  config.filter_redirect << HouseholdApp::RequestLogger::PUBLIC_LINKS
end
