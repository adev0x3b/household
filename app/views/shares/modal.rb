# frozen_string_literal: true

# Sharing one thing (Shareable, SharesController): who has it, each with a
# button to stop, then the rest of the owner's housemates to pick from, and
# Share in the footer. Drawn again in place after every share or unshare
# (dom_id), so the picker never offers someone who already has it.
class Views::Shares::Modal < Views::Base
  def self.dom_id(thing) = "share-modal-#{::Shares::Paths.key(thing)}"

  # candidates: the housemates it can still be shared with, by name.
  def initialize(thing:, candidates:)
    @thing = thing
    @candidates = candidates
  end

  def view_template
    render Components::Modal.new(size: :small, section:, id: self.class.dom_id(@thing)) do |modal|
      modal.modal_header(title: wording(:title), subtitle: wording(:subtitle), icon: "fa-share-nodes")
      modal.modal_form(url: ::Shares::Paths.new(@thing).shares, method: :post, scope: :share, data: { turbo_stream: true }) do |f|
        modal.modal_body do
          picker(f)
          render Views::Shares::List.new(thing: @thing, place: :modal)
        end
        modal.modal_footer(dismiss: t("modal.done")) do
          div(class: "modal__footer-main") { f.submit t("shares.share"), class: "modal__btn modal__btn--primary" } if @candidates.any?
        end
      end
    end
  end

  private

  def picker(form)
    if @candidates.empty?
      render Components::EmptyState.new(icon: "fa-user-group", message: t("shares.no_one_left"))
      return
    end

    render Components::Field.new(label: t("shares.with_label"), control_id: "share_profile_id", select: true, class: "share-picker") do
      names = Profiles::DisplayNames.new(@candidates)
      form.select :profile_id, @candidates.map { [ names.of(_1), _1.id ] },
                  { prompt: t("shares.select_placeholder") }, required: true
    end
  end

  # A kind's own words: shares.things.<kind>.title / .subtitle, with the thing's name.
  def wording(part) = t("shares.things.#{kind}.#{part}", name: @thing.shared_name)

  def kind = @thing.class.base_class.model_name.i18n_key

  def section = @thing.section.to_sym
end
