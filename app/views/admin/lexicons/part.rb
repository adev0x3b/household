# frozen_string_literal: true

# A part of a language's page under its own collapsible section, whose open
# or closed state is remembered per import, so the page's polling doesn't
# undo the admin's click.
class Views::Admin::Lexicons::Part < Views::Base
  private

  # owner: the import shown, else the language's code when nothing is imported.
  def section(owner, key, title:, open:, result: nil, &)
    render Components::Disclosure.new(key: "lexicon-#{owner}-#{key}", title: title, open: open, result: result, &)
  end
end
