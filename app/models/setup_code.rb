# frozen_string_literal: true

# The one-time code that opens the setup page of a copy nobody has signed in
# to yet, so whoever finds the address first can't make themselves its admin.
# Sixteen characters from an alphabet without 0, O, 1 and I, printed in
# groups of four; only the digest of the characters is kept.
#
#   code = SetupCode.generate          # "K7QM-2XRD-9VWP-HC4T"
#   SetupCode.digest(code)             # SHA-256, in hex, of "K7QM2XRD9VWPHC4T"
#   SetupCode.accepts?("k7qm 2xrd 9vwp hc4t", digest)   # true
module SetupCode
  ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  LENGTH = 16
  GROUP = 4

  def self.generate = SecureRandom.alphanumeric(LENGTH, chars: ALPHABET.chars).scan(/.{#{GROUP}}/o).join("-")

  # Case, spaces and dashes are how the code was printed or typed, not part of it.
  def self.digest(code) = Digest::SHA256.hexdigest(code.to_s.upcase.gsub(/[\s-]/, ""))

  def self.accepts?(typed, digest)
    typed.present? && digest.present? && ActiveSupport::SecurityUtils.secure_compare(digest(typed), digest)
  end
end
