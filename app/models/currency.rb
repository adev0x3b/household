# frozen_string_literal: true

# A currency by its ISO 4217 code: how many decimals its amounts have and
# the symbol it is shown with. A household may count in any three capitals,
# so a code it doesn't know has two decimals and shows as itself.
class Currency < Data.define(:code)
  # The codes ISO 4217 gives no minor unit: a yen has no cents.
  WITHOUT_MINOR_UNITS = %w[BIF CLP DJF GNF ISK JPY KMF KRW PYG RWF UGX UYI VND VUV XAF XOF XPF].freeze
  SYMBOLS = { "EUR" => "€", "USD" => "$", "GBP" => "£", "CHF" => "CHF", "JPY" => "¥" }.freeze

  def decimals = WITHOUT_MINOR_UNITS.include?(code) ? 0 : 2

  def symbol = SYMBOLS.fetch(code, code)

  # The smallest amount it has, as a number field's step.
  def step = decimals.zero? ? "1" : "0.01"
end
