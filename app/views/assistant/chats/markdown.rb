# frozen_string_literal: true

# A chat message's text, drawn from the little Markdown the assistant
# writes: paragraphs split on blank lines, runs of "- " or "1." lines as a
# list, and **bold**. Everything else stays text, so a reply can never
# bring HTML of its own.
class Views::Assistant::Chats::Markdown < Views::Base
  LIST_ITEM = /\A\s*([-*•]|\d+\.)\s+/
  BOLD = /(\*\*[^*]+\*\*)/
  BOLD_PART = /\A\*\*[^*]+\*\*\z/

  def initialize(text)
    @text = text.to_s
  end

  def view_template
    @text.split(/\n{2,}/).each { |block| render_block(block) }
  end

  private

  # A block's list lines and its other lines take turns, each run drawn as
  # what it is.
  def render_block(block)
    lines = block.lines.map(&:rstrip).reject(&:empty?)
    lines.chunk_while { |line, following| list_item?(line) == list_item?(following) }.each do |run|
      list_item?(run.first) ? list(run) : paragraph(run)
    end
  end

  def list_item?(line) = line.match?(LIST_ITEM)

  def list(lines)
    ul(class: "assistant-message__list") do
      lines.each { |line| li { inline(line.sub(LIST_ITEM, "")) } }
    end
  end

  def paragraph(lines)
    p(class: "assistant-message__paragraph") do
      lines.each_with_index do |line, index|
        br if index.positive?
        inline(line)
      end
    end
  end

  def inline(text)
    text.split(BOLD).each do |part|
      if part.match?(BOLD_PART)
        strong { part.delete_prefix("**").delete_suffix("**") }
      else
        plain(part)
      end
    end
  end
end
