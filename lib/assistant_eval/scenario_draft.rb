# frozen_string_literal: true

# A scenario being written in the eval dashboard: form fields in, a
# validated Scenario (and its YAML file) out. Expectations are edited as
# rows of a check name plus its argument written as YAML.
#
#   draft = ScenarioDraft.from_scenario(Scenario.find("04_lab_report_alone"))
#   draft.assign(params); draft.save!    # writes eval/assistant/scenarios/<name>.yml
#   draft.write_temp!                    # a throwaway copy for a one-off run
module AssistantEval
  class ScenarioDraft
    include ActiveModel::Model
    include ActiveModel::Attributes

    NAME_FORMAT = /\A\d{2}_[a-z0-9_]+\z/
    DATED = /\A@(\d{4}-\d{2}-\d{2})\s+(.*)\z/m
    BUTTONS = %w[!confirm !undo].freeze
    DRAFTS_DIR = "tmp/assistant_evals/drafts"

    attribute :name, :string
    attribute :original_name, :string
    attribute :description, :string
    attribute :today, :string
    attribute :seed, default: -> { [] }
    attribute :messages, default: -> { [] }
    attribute :expect, default: -> { [] } # [{ "check" => "lab_values", "argument" => "Cobalamin: 250" }]
    attribute :tags, default: -> { [] }
    attribute :locale, :string, default: Scenario::DEFAULT_LOCALE

    validate :name_is_well_formed, :name_is_free, :today_is_a_date, :messages_are_playable, :seeds_exist, :expectations_are_valid, :tags_are_words
    validate :has_expectations, on: :save

    def self.from_scenario(scenario)
      new(name: scenario.name, original_name: scenario.name, description: scenario.description, today: scenario.today.iso8601,
          seed: scenario.seed, messages: scenario.messages, tags: scenario.tags, locale: scenario.locale,
          expect: scenario.expect.flat_map { |entry| entry.map { |check, argument| { "check" => check.to_s, "argument" => dump(argument) } } })
    end

    # A real chat replayed as a scenario: the user's messages (a
    # later day gets its "@date"), Apply/Undo presses as buttons, and photos
    # as a "!photo" turn with the text read from them (pages split on "---"
    # lines), replayed through the same note. Expectations are left to fill in.
    def self.from_chat(chat)
      zone = chat.time_zone_or_default
      turns = ::Assistant::Trace.new(chat).turns.select(&:user)
      first_day = turns.first&.at&.in_time_zone(zone)&.to_date || Date.current
      messages = turns.flat_map do |turn|
        day = turn.at.in_time_zone(zone).to_date
        text = photo_text(turn) || turn.user
        [ day == first_day ? text : "@#{day.iso8601} #{text}", *buttons(turn) ]
      end
      new(name: Scenario.next_name("from chat #{chat.id}"), description: "Replayed from chat ##{chat.id}.",
          today: first_day.iso8601, messages: messages, expect: [])
    end

    def self.dump(value) = YAML.dump(value).delete_prefix("---").delete_suffix("...\n").strip

    def self.photo_text(turn)
      text = ::Assistant::PhotoMessage.new(turn.user).photo_text
      return if text.nil?

      pages = text.split(/^Page \d+ of \d+:\n/).map { |page| page.strip.delete_suffix(::Assistant::PhotoMessage::UNREADABLE_PAGE).strip }
      pages.shift if pages.first&.empty? && pages.size > 1
      "!photo\n#{pages.join("\n---\n")}"
    end

    def self.buttons(turn)
      turn.steps.filter_map do |step|
        next unless step.kind == :note
        next "!confirm" if step.text.to_s.include?("The user pressed Apply")

        "!undo" if step.text.to_s.include?("The user pressed Undo")
      end
    end
    private_class_method :photo_text, :buttons

    # Form params: seed and messages as arrays, expect as rows.
    def assign(params)
      assign_attributes(
        name: params[:name].to_s.strip, description: params[:description].to_s.strip, today: params[:today].to_s.strip,
        seed: Array(params[:seed]).compact_blank, tags: params[:tags].to_s.downcase.split(/[\s,]+/).compact_blank.uniq,
        locale: params[:locale].presence || locale,
        messages: Array(params[:messages]).map { |m| m.to_s.strip.gsub("\r\n", "\n") }.compact_blank,
        expect: Array(params[:expect]).map { |row| { "check" => row[:check].to_s, "argument" => row[:argument].to_s } }
          .reject { |row| row["check"].blank? }
      )
      self
    end

    def persisted? = original_name.present?

    def to_scenario
      Scenario.new(name: name, description: description.to_s, today: Date.iso8601(today), seed: seed, messages: messages,
                   expect: expect.map { |row| { row["check"] => parse(row["argument"]) } }, tags: tags,
                   locale: locale.presence || Scenario::DEFAULT_LOCALE)
    end

    def save!
      raise ActiveModel::ValidationError, self unless valid?(:save)

      write(Scenario.dir.join("#{name}.yml"))
      old = Scenario.dir.join("#{original_name}.yml") if original_name.present? && original_name != name
      old.delete if old&.exist?
      self.original_name = name
      true
    end

    # A copy for a one-off run from the editor; returns its path.
    def write_temp!
      raise ActiveModel::ValidationError, self unless valid?

      # Its own directory, so the file (and the run's scenario name) is exactly the draft's name.
      dir = Rails.root.join(DRAFTS_DIR, SecureRandom.hex(4))
      FileUtils.mkdir_p(dir)
      dir.join("#{name}.yml").tap { |path| write(path) }
    end

    # Hand-written files may carry comments; saving from the form drops them.
    def source_has_comments?
      path = Scenario.dir.join("#{original_name}.yml") if original_name.present?
      path&.exist? && path.read.match?(/^\s*#/)
    end

    private

    def write(path)
      tmp = "#{path}.tmp"
      File.write(tmp, to_scenario.to_yaml)
      File.rename(tmp, path)
    end

    def parse(text) = YAML.safe_load(text.to_s, permitted_classes: [ Date ])

    def name_is_well_formed
      errors.add(:name, :name_format) unless name.to_s.match?(NAME_FORMAT)
    end

    def name_is_free
      return if name == original_name || errors.include?(:name)

      errors.add(:name, :taken) if Scenario.dir.join("#{name}.yml").exist?
    end

    def today_is_a_date
      Date.iso8601(today.to_s)
    rescue Date::Error
      errors.add(:today, :not_a_date)
    end

    def messages_are_playable
      errors.add(:messages, :none) if messages.empty?
      messages.each_with_index do |message, i|
        if message.start_with?("!") && !BUTTONS.include?(message) && !message.match?(Runner::PHOTO)
          errors.add(:messages, :unknown_button, row: i + 1, buttons: BUTTONS.join(", "))
        elsif (dated = message.match(DATED))
          Date.iso8601(dated[1])
        end
      rescue Date::Error
        errors.add(:messages, :bad_date, row: i + 1)
      end
    end

    def seeds_exist
      unknown = seed - Seeds.names
      errors.add(:seed, :unknown, names: unknown.join(", ")) if unknown.any?
    end

    def expectations_are_valid
      expect.each_with_index do |row, i|
        next errors.add(:expect, :unknown_check, row: i + 1, check: row["check"]) if Checks.named(row["check"]).nil?

        errors.add(:expect, :missing_value, row: i + 1, check: row["check"]) if parse(row["argument"]).nil?
      rescue Psych::Exception => e
        errors.add(:expect, :bad_yaml, row: i + 1, check: row["check"], message: e.message.truncate(80))
      end
    end

    def tags_are_words
      odd = tags.grep_v(/\A[a-z0-9_-]+\z/)
      errors.add(:tags, :not_words, tags: odd.join(", ")) if odd.any?
    end

    def has_expectations
      errors.add(:expect, :none) if expect.empty?
    end
  end
end
