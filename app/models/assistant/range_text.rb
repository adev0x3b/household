# frozen_string_literal: true

# Reads a reference range from the way people say it, so the model can pass
# on the user's words, as small models do anyway, instead of turning them
# into bounds itself.
#
#   RangeText.parse("150 low 250 high 80 critically low 300 critically high")
#   # => { low: 150, high: 250, critical_low: 80, critical_high: 300 }
#   RangeText.parse("good between 20 and 50")  # => { low: 20, high: 50 }
#   RangeText.parse("8.5-10")                  # => { low: 8.5, high: 10 }
#   RangeText.parse("below 0.8 is good, 0.8 is normal, 1 is high, 1.4 is critically high")
#   # => { high: 0.8, critical_high: 1.4 }
#
# The rules run in order: critical bounds, explicit ranges ("between",
# "x-y"), "below" and "above", then values labelled low or high. A later
# rule never overwrites an earlier one. English and Italian.
module Assistant
  module RangeText
    NUM = /(\d+(?:[.,]\d+)?)/
    CRITICAL = /(?:critically|critical|critico|critica|criticamente)/
    LOW = /(?:low|basso|bassa)/
    HIGH = /(?:high|alto|alta)/
    # A range as a report's column prints it: "70 - 100", "0,4-4,0", "< 35",
    # "fino a 200", "up to 200".
    PRINTED = /\d[\d.,]*\s*[-–]\s*\d|[<>≤≥]\s*\d|\b(?:fino a|up to|inferiore a|superiore a)\s+\d/i

    module_function

    def parse(text)
      rest = " #{text.to_s.downcase.tr("–—", "--")} "
      bounds = {}

      take = lambda do |key, pattern|
        rest = rest.sub(pattern) do
          bounds[key] ||= number(Regexp.last_match[:n])
          " "
        end
      end

      # 1. critical bounds, either word order
      take.(:critical_low, /(?<n>#{NUM})\s*\(?\s*(?:is\s+|è\s+)?#{CRITICAL}\s*#{LOW}/o)
      take.(:critical_low, /#{CRITICAL}\s*#{LOW}\s*(?:is\s+|at\s+|below\s+|è\s+|a\s+)?(?<n>#{NUM})/o)
      take.(:critical_high, /(?<n>#{NUM})\s*\(?\s*(?:is\s+|è\s+)?#{CRITICAL}\s*#{HIGH}/o)
      take.(:critical_high, /#{CRITICAL}\s*#{HIGH}\s*(?:is\s+|at\s+|above\s+|è\s+|a\s+)?(?<n>#{NUM})/o)

      # 2. explicit ranges
      if (m = rest.match(/(?:between|tra|fra)\s+#{NUM}\s+(?:and|e)\s+#{NUM}/o) || rest.match(/#{NUM}\s*(?:-|to|a)\s*#{NUM}/o))
        bounds[:low] ||= number(m[1])
        bounds[:high] ||= number(m[2])
        rest = rest.sub(m[0], " ")
      end

      # 3. below / above
      take.(:high, /(?:below|under|less than|up to|<|sotto|inferiore a|fino a)\s*(?<n>#{NUM})/o)
      take.(:low, /(?:above|over|more than|at least|>|sopra|superiore a|almeno)\s*(?<n>#{NUM})/o)

      # 4. values labelled low / high
      take.(:low, /(?<n>#{NUM})\s*\(?\s*(?:is\s+|è\s+)?#{LOW}/o)
      take.(:low, /#{LOW}\s*(?:is\s+|at\s+|è\s+)?(?<n>#{NUM})/o)
      take.(:high, /(?<n>#{NUM})\s*\(?\s*(?:is\s+|è\s+)?#{HIGH}/o)
      take.(:high, /#{HIGH}\s*(?:is\s+|at\s+|è\s+)?(?<n>#{NUM})/o)

      bounds.compact
    end

    # Whether a line of a report carries a range in it.
    def printed?(line) = line.match?(PRINTED)

    def number(text) = Float(text.to_s.tr(",", "."), exception: false)
  end
end
