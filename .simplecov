# frozen_string_literal: true

# Coverage of every `bin/rails test` run, started at the top of
# test/test_helper.rb (open coverage/index.html, or `bundle exec simplecov
# open`). Minitest's parallel workers each measure their share; the parent
# process merges them, writes the report and checks the floor, so CI fails
# when coverage drops below it. Raise the floor as tests are added; never
# lower it to make a change pass.
SimpleCov.configure do
  enable_coverage :branch
  # Minitest's `parallelize` forks the workers that run the tests.
  merge_subprocesses true
  # Every file counts, loaded by a test or not (the test environment only
  # eager-loads on CI): an untested file is 0%, not absent.
  cover "{app,lib}/**/*.rb"

  # One group per layer of app/, as the directory is laid out, and one for lib.
  Dir.children("app").sort.each do |layer|
    group layer.humanize, "app/#{layer}" if Dir["app/#{layer}/**/*.rb"].any?
  end
  group "Libraries", "lib"

  # The floor is the whole suite's, so it is checked where the whole suite
  # runs (CI, and bin/ci, which sets CI too), never when one file does. It
  # sits just under what the whole suite, system tests included, measured
  # when it was set; the layers that hold the rules (models, services,
  # policies) keep their branches at 90.
  unless ENV["CI"].to_s.empty?
    coverage :line, minimum: 96.5
    coverage :branch do
      minimum 83
      %w[Models Services Policies].each { |layer| minimum 90, per: group(layer) }
    end
  end
  deprecations :raise
end
