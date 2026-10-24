# frozen_string_literal: true

require "test_helper"

# The one rule for a migration that needs the app stopped, shared by
# bin/held-migrations (a checkout) and Delivery::HeldMigrations (GitHub).
class HeldMigrationsTest < ActiveSupport::TestCase
  HELD = <<~RUBY
    class RebuildCalendarCore < ActiveRecord::Migration[8.1]
      def up
        safety_assured { rename_table :events, :series }
      end
    end
  RUBY

  MARKED = <<~RUBY
    class RemoveSsn < ActiveRecord::Migration[8.1]
      def change
        # zero-downtime: Profile has ignored ssn since the previous deploy
        safety_assured { remove_column :profiles, :ssn }
      end
    end
  RUBY

  PLAIN = <<~RUBY
    class AddNotes < ActiveRecord::Migration[8.1]
      def change
        add_column :events, :notes, :text
      end
    end
  RUBY

  test "safety_assured without the marker is held; with it, or without safety_assured, it isn't" do
    assert HeldMigrations.held?(HELD)
    assert_not HeldMigrations.held?(MARKED)
    assert_not HeldMigrations.held?(PLAIN)
    assert_not HeldMigrations.held?(nil)
  end

  test "the marker counts only at the start of a line, indented or not" do
    assert_not HeldMigrations.held?(HELD.sub("def up", "# zero-downtime: the old version never reads events\n  def up"))
    assert HeldMigrations.held?(HELD.sub("def up", "def up # zero-downtime: not really"))
  end

  test "only migration files are looked at" do
    assert HeldMigrations.migration?("db/migrate/20261011090000_rebuild_calendar_core.rb")
    assert_not HeldMigrations.migration?("db/schema.rb")
    assert_not HeldMigrations.migration?("db/migrate/notes.txt")
    assert_not HeldMigrations.migration?("app/models/db/migrate/x.rb")
  end

  test "among picks the held migrations out of the added files, reading each one's source" do
    sources = { "db/migrate/1_held.rb" => HELD, "db/migrate/2_marked.rb" => MARKED, "db/migrate/3_plain.rb" => PLAIN, "db/schema.rb" => HELD }
    read = []
    held = HeldMigrations.among(sources.keys) { |path| read << path; sources.fetch(path) }

    assert_equal [ "db/migrate/1_held.rb" ], held
    assert_not_includes read, "db/schema.rb"
  end

  test "the script agrees with the rule on this repository's own history" do
    skip "no git history here" unless system("git", "rev-parse", "--verify", "HEAD~1", out: File::NULL, err: File::NULL)

    output = IO.popen([ Rails.root.join("bin/held-migrations").to_s, "HEAD~1", "HEAD" ], err: File::NULL, &:read)
    assert_includes [ 0, 1 ], $?.exitstatus, "the script should answer 0 or 1 on two real commits"
    assert_equal output.lines(chomp: true).uniq, output.lines(chomp: true)
  end
end
