# frozen_string_literal: true

# The assistant's vocabulary for changing the database. The write tools
# (Assistant::ChangeTool) turn a model's call into operations, kept as plain
# data so a change set can be stored, shown and checked again later:
#
#   { "intent" => 0, "op" => "create", "type" => "lab_test_result", "ref" => nil, "as" => "$lab", "fields" => {…} }
#
# One class per op knows how to check it without writing, save it and
# describe it.
module Assistant
  module Operations
    CLASSES = { "create" => Create, "update" => Update, "complete" => Complete, "uncomplete" => Uncomplete,
                "set_status" => SetStatus, "delete" => Delete, "set_range" => SetRange, "share" => Share, "unshare" => Unshare,
                "merge" => Merge }.freeze
    # Words models use for an op.
    ALIASES = { "add" => "create", "new" => "create", "record" => "create", "log" => "create", "save" => "create",
                "book" => "create", "edit" => "update", "change" => "update", "fix" => "update", "correct" => "update",
                "done" => "complete", "mark_done" => "complete", "finish" => "complete", "undo_complete" => "uncomplete",
                "status" => "set_status", "merge_into" => "merge",
                "remove" => "delete", "set_reference_range" => "set_range", "reference_range" => "set_range",
                "range" => "set_range", "set_ranges" => "set_range" }.freeze
    SPEC_KEYS = %w[intent op type ref as fields pinned].freeze

    # A spec in canonical shape: known op and type, everything else in fields.
    def self.normalize(spec)
      spec = spec.to_h.deep_stringify_keys
      fields = spec["fields"].is_a?(Hash) ? spec["fields"].dup : {}
      spec.except(*SPEC_KEYS, "id").each { |key, value| fields[key] ||= value }
      op = spec["op"].to_s.strip.downcase.tr(" -", "__")
      op = ALIASES.fetch(op, op)
      type = spec["type"].to_s.strip.presence
      op = "set_range" if op.empty? && type.to_s.include?("range")
      type = "reference_range" if op == "set_range"
      type = canonical_type(type) if type
      ref = spec["ref"].presence || spec["id"].presence

      { "intent" => spec["intent"], "op" => op, "type" => type, "ref" => ref, "as" => spec["as"].presence, "fields" => fields,
        "pinned" => spec["pinned"].presence }.compact
    end

    def self.canonical_type(type)
      Resources.fetch(type).key
    rescue ArgumentError
      type
    end

    def self.build(spec, index:, context:)
      spec = normalize(spec)
      klass = CLASSES[spec["op"]]
      return Invalid.new(spec, index:, context:, reason: "unknown op #{spec["op"].inspect}; use #{CLASSES.keys.join(", ")}") if klass.nil?

      klass.new(spec, index:, context:)
    end

    # Whether a later call's spec is about the same operation as one already
    # in the set: the same op and type, and what each names agrees (each
    # op's class says what that is: Base.same_spec?).
    def self.same?(a, b)
      a = normalize(a)
      b = normalize(b)
      return false unless a["op"] == b["op"] && a["type"] == b["type"]

      CLASSES.fetch(a["op"], Base).same_spec?(a, b)
    end
  end
end
