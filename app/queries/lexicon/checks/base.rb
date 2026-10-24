# frozen_string_literal: true

module Lexicon
  module Checks
    # One kind of check: the key that names it, the keys its spec needs, and
    # what it finds in the import — whether it holds, and what was there.
    class Base
      def self.kind = raise(NotImplementedError, "#{name} names the key that marks its specs")
      def self.keys = raise(NotImplementedError, "#{name} names the keys its spec needs")

      def initialize(import, language, spec)
        @import = import
        @language = language
        @spec = spec
      end

      # [ok, got]: got is what the import holds where the check looked,
      # worded for the report.
      def call = raise(NotImplementedError, "#{self.class.name} answers call")
    end
  end
end
