# frozen_string_literal: true

module Assistant
  # A call that can't be carried out as asked, worded for the model to act
  # on (a date nobody can read, a supply never saved). Tools and operations
  # both turn it into the model's error, so it lives below both; anything
  # else raised is a bug and stays an exception.
  class Failure < StandardError; end
end
