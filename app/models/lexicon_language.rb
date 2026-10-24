# frozen_string_literal: true

# A language the lexicon knows: what to import (kaikki.org's name for it),
# how its names read, and the cases its imports are tested against the
# agent with. A new database starts with config/lexicons.yml's languages.
class LexiconLanguage < ApplicationRecord
  ROLES = %w[translated pivot].freeze
  # kaikki's codes: "it", "nb", "grc", "roa-opt"…
  CODE_FORMAT = /\A[a-z][a-z-]{1,15}\z/

  has_many :lexicon_eval_cases, dependent: :delete_all

  validates :code, presence: true, uniqueness: true, format: { with: CODE_FORMAT }
  validates :wiktionary, presence: true, uniqueness: true
  validates :role, inclusion: { in: ROLES }
  validates :head, inclusion: { in: Lexicon::Config::HEADS }
  validates :min_lemmas, numericality: { only_integer: true, greater_than: 0 }

  scope :by_code, -> { order(Arel.sql("role = 'pivot' DESC"), :code) }

  def pivot? = role == "pivot"

  def to_config
    Lexicon::Config::Language.new(code: code, wiktionary: wiktionary, role: pivot? ? "pivot" : "", head: head, min_lemmas: min_lemmas,
                                  checks: Array(checks).map { |spec| Lexicon::Config::Check.new(spec: spec.to_h.stringify_keys) })
  end

  # "Italian" for "it" (the code itself for a language that's gone).
  def self.name_of(code) = where(code: code.to_s).pick(:wiktionary) || code.to_s

  # config/lexicons.yml's languages as rows of this table.
  def self.starting_set
    Lexicon::Config.defaults.values.map do |language|
      { code: language.code, wiktionary: language.wiktionary, role: language.pivot? ? "pivot" : "translated",
        head: language.head, min_lemmas: language.min_lemmas, checks: language.checks.map(&:spec) }
    end
  end

  # Saves the starting languages the table doesn't have, from db/seeds.rb.
  # Never overwrites: once a language is here, the page owns it.
  def self.ensure_defaults!
    existing = pluck(:code)
    starting_set.each do |attributes|
      create!(attributes) unless existing.include?(attributes[:code])
    rescue ActiveRecord::RecordNotUnique
      next # another process added it meanwhile
    end
  end
end
