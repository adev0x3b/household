# frozen_string_literal: true

# Typo- and accent-tolerant matching for the assistant (Assistant::TextMatch):
# "estradio1" finds Estradiol, "unita" finds "Unità". Both extensions ship
# with PostgreSQL; creating them needs a role allowed to CREATE EXTENSION
# (the database owner on PG 13+ for these trusted ones).
class EnableTrigramSearch < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"
    enable_extension "unaccent"
  end
end
