# frozen_string_literal: true

# Where the reader is, for the navbar's parts to mark the link they're on
# (`aria-current`) and open its group: the request's path against a link's
# `href` and, when its pages live elsewhere, their prefix.
class Navbar::Location
  def initialize(current_path, root:)
    @current_path = current_path
    @root = root
  end

  # The link's own page, or one below its pages (the root: only itself).
  # pages: where the link's pages live when not under its own path
  # (/assistant opens a chat, under /assistant/chats).
  def current?(href, pages = nil)
    return false unless @current_path

    path = URI.parse(href).path
    return true if @current_path == path

    prefix = pages || path
    prefix != @root && (@current_path == prefix || @current_path.start_with?("#{prefix}/"))
  end
end
