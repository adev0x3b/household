# frozen_string_literal: true

# One assistant evaluation scenario (eval/assistant/scenarios/*.yml): what the
# user says turn by turn, what exists beforehand, and what the database must
# look like afterwards. Messages starting with "@YYYY-MM-DD " happen on that
# day; "!confirm" / "!undo" press the chat's buttons instead of talking.
# `locale` is the language the chat is in (the user's navbar choice): the
# assistant is told to reply in it, so an Italian scenario is judged on an
# Italian reply. Default en.
module AssistantEval
  Scenario = Data.define(:name, :description, :today, :seed, :messages, :expect, :tags, :locale) do
    # tags: optional labels (labs, coverage, ocr…) to filter and run groups in the dashboard.
    def initialize(tags: [], locale: Scenario::DEFAULT_LOCALE, **rest) = super(tags: Array(tags), locale: locale.to_s, **rest)

    def self.dir = @dir || Rails.root.join("eval/assistant/scenarios")

    # Tests point this at a temporary directory.
    def self.dir=(path)
      @dir = path && Pathname(path)
    end

    def self.all(filter = nil)
      Dir[dir.join("*.yml")].map { |path| load(path) }.select { |s| filter.blank? || s.name.include?(filter) }
    end

    # nil when there's no scenario of that name.
    def self.find(name)
      path = dir.join("#{name}.yml")
      name.to_s.match?(ScenarioDraft::NAME_FORMAT) && path.exist? ? load(path) : nil
    end

    def self.load(path)
      data = YAML.safe_load_file(path, permitted_classes: [ Date ])
      new(name: File.basename(path, ".yml"), description: data["description"].to_s, today: Date.parse(data.fetch("today").to_s),
          seed: Array(data["seed"]), messages: data.fetch("messages"), expect: data.fetch("expect"), tags: Array(data["tags"]),
          locale: data.fetch("locale", Scenario::DEFAULT_LOCALE))
    end

    # "skip todays dose" → "10_skip_todays_dose" (the next free number).
    def self.next_name(slug)
      taken = Dir[dir.join("*.yml")].filter_map { |path| File.basename(path)[/\A(\d{2})_/, 1]&.to_i }
      words = slug.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "").presence || "scenario"
      format("%02d_%s", (taken.max || 0) + 1, words)
    end

    # The same shape as the hand-written files; multi-line messages become block scalars.
    def to_yaml
      data = { "description" => description.presence, "tags" => tags.presence, "today" => today,
               "locale" => (locale unless locale == Scenario::DEFAULT_LOCALE), "seed" => seed.presence,
               "messages" => messages, "expect" => expect }.compact
      YAML.dump(data).delete_prefix("---\n")
    end
  end
  # A constant set after the block: inside Data.define a constant would belong to AssistantEval, not Scenario.
  Scenario::DEFAULT_LOCALE = "en"
end
