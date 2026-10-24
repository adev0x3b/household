# frozen_string_literal: true

# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"
  step "Style: JavaScript and stylesheets", "npm run lint"
  step "Style: Shell scripts", "bin/lint-shell"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  # The npm packages are lint and test tools that never ship, so only a
  # critical advisory stops a run.
  step "Security: npm audit of the lint and test tools", "npm audit --audit-level=critical"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Security: Secrets in every commit", "bin/gitleaks git --redact --no-banner"
  step "Tests: JavaScript", "npm test"
  # CI as GitHub sets it: the app eager-loaded, the coverage floor checked
  # (.simplecov), every route requested. Also: i18n keys (test/i18n_test.rb),
  # N+1s on every request, the system tests in headless Chrome with axe.
  step "Tests: Rails", "env CI=true bin/rails test:all"
end
