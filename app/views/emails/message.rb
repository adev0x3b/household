# frozen_string_literal: true

# The HTML part of every mail (ApplicationMailer#compose), drawn from its
# wording (Emails::Wording): the heading, what it says, a list, the one
# button with its address written out under it for a client that hides
# links, a closing line, and the link that stops such mail. No image, no
# remote content, nothing that tells anyone the mail was opened.
class Views::Emails::Message < Views::Base
  # Mail clients load no stylesheet and keep little of a <style>, so each
  # colour (Theme's mail colours) is written on the element it paints.
  FONT = "-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif"

  def initialize(wording)
    @wording = wording
  end

  # A mail is a whole document: nothing goes before its doctype.
  def before_template = nil

  def view_template
    doctype
    html(lang: I18n.locale) do
      head do
        meta(charset: "utf-8")
        meta(name: "viewport", content: "width=device-width,initial-scale=1")
        meta(name: "color-scheme", content: "light")
        title { @wording.subject }
      end
      body(style: "margin: 0; padding: 0; background: #{Theme::MAIL_PAGE};") { frame }
    end
  end

  private

  # Tables, because the clients that draw mail with a word processor's
  # engine centre and narrow nothing else.
  def frame
    table(role: "presentation", width: "100%", cellpadding: "0", cellspacing: "0", style: "background: #{Theme::MAIL_PAGE};") do
      tr do
        td(align: "center", style: "padding: 24px 12px;") do
          table(role: "presentation", width: "100%", cellpadding: "0", cellspacing: "0",
                style: "max-width: 560px; background: #{Theme::MAIL_CARD}; border-radius: 12px;") do
            tr do
              td(style: "padding: 28px 24px; font-family: #{FONT}; font-size: 16px; line-height: 1.5; color: #{Theme::MAIL_TEXT};") { content }
            end
          end
        end
      end
    end
  end

  def content
    h1(style: "margin: 0 0 16px; font-size: 18px; font-weight: 700;") { @wording.heading }
    @wording.paragraphs.each { |paragraph| p(style: "margin: 0 0 16px;") { paragraph } }
    items if @wording.items.any?
    action if @wording.action
    p(style: "margin: 24px 0 0; font-size: 13px; color: #{Theme::MAIL_MUTED};") { @wording.closing } if @wording.closing
    unsubscribe if @wording.unsubscribe
  end

  def items
    ul(style: "margin: 0 0 16px; padding-left: 20px;") do
      @wording.items.each { |item| li(style: "margin: 0 0 6px;") { item } }
    end
  end

  def unsubscribe
    p(style: "margin: 8px 0 0; font-size: 13px;") do
      a(href: @wording.unsubscribe.url, style: "color: #{Theme::MAIL_MUTED};") { @wording.unsubscribe.label }
    end
  end

  def action
    p(style: "margin: 8px 0 8px;") do
      a(href: @wording.action.url, style: "display: inline-block; padding: 10px 20px; border-radius: 8px; background: #{Theme::ACCENT}; " \
                                          "color: #{Theme::PAGE}; font-weight: 600; text-decoration: none;") do
        @wording.action.label
      end
    end
    p(style: "margin: 0 0 16px; font-size: 13px; color: #{Theme::MAIL_MUTED}; word-break: break-all;") do
      a(href: @wording.action.url, style: "color: #{Theme::MAIL_MUTED};") { @wording.action.url }
    end
  end
end
