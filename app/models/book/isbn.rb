# frozen_string_literal: true

# An ISBN as typed or scanned. A book's barcode is an EAN-13 that *is* its
# ISBN-13 (978 or 979 prefix); older books carry an ISBN-10. Both come out
# as the 13 digits the app stores, or nil when the digits don't check out.
# The 5-digit price add-on printed next to the barcode is never one.
#
#   Book::Isbn.normalize("0-306-40615-2")   # => "9780306406157"
#   Book::Isbn.normalize("9780306406158")   # => nil (bad checksum)
module Book::Isbn
  ISBN13 = /\A97[89]\d{10}\z/
  ISBN10 = /\A\d{9}[\dX]\z/

  module_function

  def normalize(raw)
    digits = digits_of(raw)
    case digits.length
    when 13 then digits if valid13?(digits)
    when 10 then to_isbn13(digits) if valid10?(digits)
    end
  end

  def digits_of(raw) = raw.to_s.upcase.delete("^0-9X")

  def valid13?(digits) = digits.match?(ISBN13) && check13(digits[0, 12]) == digits[12].to_i

  def valid10?(digits)
    return false unless digits.match?(ISBN10)

    digits.chars.each_with_index.sum { |char, index| (char == "X" ? 10 : char.to_i) * (10 - index) } % 11 == 0
  end

  def to_isbn13(digits)
    core = "978#{digits[0, 9]}"
    "#{core}#{check13(core)}"
  end

  # The check digit that completes twelve digits.
  def check13(twelve) = (10 - (twelve.chars.map(&:to_i).each_with_index.sum { |n, i| i.even? ? n : n * 3 } % 10)) % 10
end
