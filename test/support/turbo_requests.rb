# frozen_string_literal: true

# A form's submission as Turbo sends it from a page: it accepts a Turbo
# Stream ahead of HTML, and the browser names the page it was sent from. A
# test that leaves either out asks for an answer no browser ever gets.
#
#   delete book_path(book), headers: submitted_from(book_path(book))
#   assert_redirected_to books_path
module TurboRequests
  ACCEPT = "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"

  def submitted_from(path) = { "Accept" => ACCEPT, "Referer" => "http://www.example.com#{path}" }
end
