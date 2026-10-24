# frozen_string_literal: true

module Releases
  # The release's page: whether the update stops the app while the database
  # changes, then what main gained since the release before.
  class Notes
    def initialize(plan, image:, downtime_seconds: nil)
      @plan = plan
      @image = image
      @downtime_seconds = downtime_seconds
    end

    def to_s = [ *stop, *changes, "The image: `#{@image}`" ].join("\n\n") + "\n"

    private

    def stop
      return [] if @plan.stopped_migrations.empty?

      downtime = " Production was behind its maintenance page for #{@downtime_seconds} seconds." if @downtime_seconds
      [ "**This update stops the app while it changes the database.**#{downtime} " \
        "The migrations that need it: #{@plan.stopped_migrations.map { "`#{_1}`" }.join(", ")}." ]
    end

    def changes
      return [ "## The first release" ] unless @plan.previous

      [ "## What's new since #{@plan.previous}", @plan.changes.map { "- #{_1.title} (#{_1.reference})" }.join("\n") ]
    end
  end
end
