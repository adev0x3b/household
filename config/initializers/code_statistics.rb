# frozen_string_literal: true

# `bin/rails stats` counts every layer the app keeps its code in, and their
# tests, not only the folders Rails knows about. At
# boot, as Pundit registers its own: the stats command boots the app and
# loads no rake file.
require "rails/code_statistics"

{ "Components" => "app/components", "Presenters" => "app/presenters", "Services" => "app/services", "Queries" => "app/queries", "Reports" => "app/reports",
  "Clients" => "app/clients", "Broadcasters" => "app/broadcasters", "Assistant tools" => "app/tools", "Assistant agents" => "app/agents" }
  .each { |label, path| Rails::CodeStatistics.register_directory(label, path) }

{ "Component tests" => "test/components", "View tests" => "test/views", "Presenter tests" => "test/presenters",
  "Service tests" => "test/services", "Query tests" => "test/queries", "Report tests" => "test/reports",
  "Client tests" => "test/clients", "Broadcaster tests" => "test/broadcasters", "Assistant tool tests" => "test/tools",
  "Library tests" => "test/lib", "Test support" => "test/support" }
  .each { |label, path| Rails::CodeStatistics.register_directory(label, path, test_directory: true) }
