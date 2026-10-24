# frozen_string_literal: true

# When this process came up: /admin/deployment shows it next to the version
# the image was built from (APP_VERSION). Read through Deployment.booted_at.
Rails.application.config.x.deployment.booted_at = Time.current
