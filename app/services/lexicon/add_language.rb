# frozen_string_literal: true

# Adds a language kaikki.org has, from its English name: the extract must
# exist, and its code is read from its first entries (Lexicon::Source#peek)
# — never typed. The LexiconLanguage comes back saved, or with errors on
# :wiktionary saying why not (shown on the admin page's form, or by
# lexicon:add).
#
#   result = Lexicon::AddLanguage.call("Spanish", head: "first")
#   result.success?   # => true, result.language.code == "es"
module Lexicon
  class AddLanguage
    Result = ServiceResult.define(:language)

    def self.call(name, **options)
      language = add(name, **options)
      Result.new(language: language, error: (:invalid unless language.persisted?))
    end

    # peek: ->(url) { { code:, language: } } in tests.
    def self.add(name, head:, peek: ->(url) { Source.new(url: url).peek })
      name = name.to_s.strip
      language = LexiconLanguage.new(wiktionary: name, head: head.presence || "first", role: "translated")
      return language.tap { _1.errors.add(:wiktionary, :blank) } if name.empty?
      return refuse(language, "already_here", language: name) if LexiconLanguage.exists?(wiktionary: name)

      language.code = peek.call(Config.parse("xx", "wiktionary" => name).url)[:code]
      taken = LexiconLanguage.find_by(code: language.code)
      return refuse(language, "code_taken", code: language.code, language: name, existing: taken.wiktionary) if taken

      language.save
      language
    rescue Source::Error => e
      refuse(language, "not_on_kaikki", language: name, error: e.message)
    end

    def self.refuse(language, key, **values)
      language.errors.add(:wiktionary, I18n.t("admin.lexicons.add.#{key}", **values))
      language
    end
    private_class_method :add, :refuse
  end
end
