# frozen_string_literal: true

# Something a person can do to an item or a page, whichever way it is
# drawn: as a round button on its item (Components::ItemAction), an entry
# behind an item's "more" (Components::ItemMenu), or a button in the top
# bar (Components::PageControls).
#
# `turbo_stream:` opens a modal. `method:` changes something, so Turbo
# sends it with that method, since a GET never does. `confirm:` asks first.
# `download:` posts outside Turbo: the server records the download and
# answers with the file's address, which the browser saves, where through
# Turbo the file would be fetched into the page and a link to it prefetched
# on hover. `danger:` deletes or undoes something, so it goes last, set
# apart. `active:` marks a toggle that is on, its label saying what
# pressing it does. Without `href:` it is a button a Stimulus controller
# runs (`data:`).
#
#   Components::Action.new(href: edit_recipe_path(recipe), icon: "fa-pen", label: t("recipes.card.edit"), turbo_stream: true)
#   Components::Action.new(href: recipe_path(recipe), icon: "fa-trash", label: t("recipes.card.destroy"),
#                          method: :delete, confirm: t("recipes.confirm_destroy"), danger: true)
#
# The HTTP method is kept as `verb`, since a member named `method` would
# hide Object#method; it is given as `method:`, as to Rails' button_to.
Components::Action = Data.define(:icon, :label, :href, :turbo_stream, :verb, :confirm, :download, :danger, :active, :data) do
  def initialize(icon:, label:, href: nil, turbo_stream: false, method: nil, confirm: nil, download: false, danger: false, active: false, data: {})
    super(icon:, label:, href:, turbo_stream:, verb: method, confirm:, download:, danger:, active:, data:)
  end
end
