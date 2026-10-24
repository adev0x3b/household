# frozen_string_literal: true

# The tools that change records. Each has a small schema of its own,
# because a small model fills typed fields far more reliably than one generic
# "fields" object, and turns its arguments into operations for
# ChangeSets::Submit, so every change has the same card and the same Undo.
# Schemas carry no example values: small models copy them into real records.
module Assistant
  class ChangeTool < Tool
    # What update_record and delete_records take as type: every kind the
    # registry knows, so a new resource is theirs the day it is registered.
    TYPES = Resources.keys.freeze
    FREQUENCIES = %w[daily weekly monthly yearly].freeze
    PAYMENT = { type: "string", enum: Transaction::Details.payment_methods.keys, description: "How it was paid — only if the user said so" }.freeze
    DATE = { type: "string", description: "YYYY-MM-DD or the user's words (\"a week ago\", \"this Friday\")" }.freeze
    CONFIRM = { type: "boolean", description: "Only when the user said to go ahead although something similar already exists" }.freeze
    # A collection by the user's word for it (Healthcare calls them
    # therapies). It is matched to a saved one, a healthcare one first, or
    # created.
    THERAPY = { type: "string", description: "The therapy it belongs to, by name, if the user said so" }.freeze
    MEMBER = { type: "string", description: "A household member this money is with (paid by them, or to them), by name — not for shops or doctors" }.freeze
    # A search result or a duplicate warning shows a series' id as
    # "event_id", and models echo that key back as an argument of its own
    # instead of folding it into ref, so every tool that takes ref takes it.
    EVENT_ID = { type: "integer", description: "A series' event_id, shown by search_records or a duplicate warning — only if ref isn't given" }.freeze
    USES = {
      type: "array", description: "Supplies used (a needle, a syringe…) — only if the user said so",
      items: { type: "object", properties: { supply: { type: "string" }, quantity: { type: "number", description: "Default 1" } },
               required: %w[supply] }
    }.freeze
    RECURRENCE = {
      repeat: { type: "string", enum: FREQUENCIES },
      every: { type: "integer", description: "Repeat every N days/weeks/…" },
      days: { type: "array", items: { type: "string", enum: Events::RecurrenceRule::WEEK_DAYS }, description: "Weekly on these days" },
      ends: DATE.merge(description: "Last day it happens (to stop it after today: today)")
    }.freeze
    # The doses of a day, as FHIR's timeOfDay and "when" name them.
    TIMES = {
      type: "array", items: { type: "string" },
      description: "Medication only: when each dose of the day is taken — HH:MM, or breakfast / lunch / dinner / bedtime; one entry per dose a day"
    }.freeze

    def self.write_tool_names = BookkeeperAgent::TOOLS.select { |tool| tool < ChangeTool }.map(&:tool_name)

    # A change that worked shows as its card; its line is seen on a failure.
    def self.activity_key = "change"

    private

    # Blank fields are dropped, so an argument the model left empty never
    # overwrites what the user said earlier.
    def submit(ops, confirm: false)
      ops = ops.map { |spec| spec.merge(fields: compact_fields(spec[:fields])).compact }
      ops = new_collections_for(ops) + ops
      ChangeSets::Submit.call(chat: chat, operations: ops, confirm: confirm)
    rescue ChangeSets::Submit::Mistake => e
      fail!(e.message)
    end

    # A therapy the user named that isn't saved yet is created (a healthcare
    # collection) with the records that belong to it, so a small model
    # needn't remember to call add_collection first. The name is matched
    # like every catalog name, typos included, so a misspelled therapy links
    # to the saved one instead of making a second.
    def new_collections_for(ops)
      names = ops.filter_map { |spec| spec[:fields]["therapy"] if spec[:op].to_s == "create" && spec[:type].to_s != "collection" }
      names.select { |name| name.is_a?(String) && name.squish.present? }
        .uniq { |name| name.squish.downcase }
        .reject { |name| Resources.collection_named(profile, name) }
        .map { |name| { op: "create", type: "collection", fields: { "name" => name.squish, "section" => "healthcare" } } }
    end

    def compact_fields(fields)
      fields.to_h.each_with_object({}) do |(key, value), kept|
        value = compact_fields(value) if value.is_a?(Hash)
        value = value.map { |item| item.is_a?(Hash) ? compact_fields(item) : item }.reject(&:blank?) if value.is_a?(Array)
        kept[key.to_s] = value unless value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end

    # A price the model gave once beside the items ("500 g of linguine for
    # 99 cents") is the price of a single item. Beside several it is a total
    # nobody can split, so it stays out and the result asks for each item's
    # price: the model must never guess a split. An item's own price wins.
    def priced_items(items, amount)
      items = items_of(items)
      return items if amount.blank? || items.size != 1 || !items.first.is_a?(Hash) || items.first["amount"].present?

      [ items.first.merge("amount" => amount) ]
    end

    # A small model often sends a list's items as plain words instead of
    # objects, and the draft reads those as the item's name or the step's
    # instruction.
    def items_of(list) = Array(list).map { |item| item.is_a?(Hash) ? item.to_h.stringify_keys : item.to_s }

    # A bare event_id, written the way ChangeSets::Resolver reads one.
    def ref_or_event_id(ref, event_id) = ref.presence || (event_id.present? ? "event_id #{event_id}" : nil)

    # The type a series' event_id means, for a model that gave event_id and
    # left type out. The two can't disagree, so there is nothing to ask.
    def type_from_event_id(event_id)
      return if event_id.blank?

      event = Event.accessible_by(profile).find_by(id: event_id)
      Resources.fetch(event.type.underscore).key if event
    end

    def member_id(words)
      return if words.blank?

      resolution = Members.new(chat.profile).resolve(words)
      fail!(resolution.problem) if resolution.problem
      fail!("several people match #{words}: #{resolution.candidates.map { |c| c[:name] }.join(", ")} — ask which one") if resolution.candidates.any?
      resolution.profile.id
    end

    # Free text that clearly names a household member becomes that member.
    # It never fails, so it is safe to try on any counterparty: a shop or a
    # doctor just doesn't match, and two candidates or none leave the text
    # as the model gave it.
    def member_id_from_text(words)
      return if words.blank?

      Members.new(chat.profile).resolve(words).profile&.id
    end

    # The RECURRENCE arguments as recurrence fields, nil when none were
    # given. Days alone mean weekly and several times alone mean daily,
    # because that is what a user who names only those means.
    def recurrence(repeat = nil, every = nil, days = nil, ends = nil, times = nil)
      days = Array(days).map { |d| d.to_s.downcase }.presence
      times = Array(times).compact_blank.map { |time| time_code(time) }.presence
      repeat = "weekly" if repeat.blank? && days
      repeat = "daily" if repeat.blank? && days.nil? && times && times.many?
      ends = date(ends.to_s, "ends")&.iso8601
      { frequency: repeat.presence, interval: every, week_days: days, ends: ends, slots: times }.compact.presence
    end
  end
end
