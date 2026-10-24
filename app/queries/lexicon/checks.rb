# frozen_string_literal: true

module Lexicon
  # A language's hand-written data checks (the `checks` of config/lexicons.yml),
  # one class per kind, each run against one import by Lexicon::Verification.
  # A check's kind is the key that names it (`form`, `means`, `synonym`,
  # `said`); a new kind is a class here and a line in `all`.
  module Checks
    def self.all = [ Form, Means, Synonym, Said ]

    # The class a spec is a check of, by the key naming it; nil when none takes it.
    def self.of(spec) = all.find { |check| spec.key?(check.kind) }

    def self.named(kind) = all.find { _1.kind == kind.to_s }
  end
end
