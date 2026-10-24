# frozen_string_literal: true

# Nearly everything a household sends is private: messages, notes, lab
# values, amounts, searches, the names of medications. So the log keeps a
# request's ids, which say what it was about, and writes [FILTERED] for every
# other parameter, secrets included, and for a nested form as a whole. A new
# field stays out of the log without anyone having to remember it.
#
# Rails applies the same list to the query string of the request line, to
# the location of a redirect, and to what a record shows when inspected.
Rails.application.config.filter_parameters += [
  /\A(?!(?:\w+_)?id\z)/
]
