# frozen_string_literal: true

# A list's name. Its items are added and changed on the list page, where it
# is also finished and reopened: reopening puts back what was bought, which
# a status picked here would skip.
class Views::GroceryLists::Modals::Form < Views::Base
  def initialize(grocery_list:, url:)
    @grocery_list = grocery_list
    @url = url
  end

  def view_template
    render Components::Modal.new(size: :small, section: :pantry) do |modal|
      modal.modal_header(title: modal_title, subtitle: modal_subtitle, icon: "fa-cart-shopping")

      render Components::Form.new(record: @grocery_list, url: @url, submit_text: submit_text, modal: modal) do |f|
        render_name_field(f)
      end
    end
  end

  private

  def modal_title
    @grocery_list.persisted? ? t("grocery_lists.form.edit_title") : t("grocery_lists.form.new_title")
  end

  def modal_subtitle
    @grocery_list.persisted? ? t("grocery_lists.form.edit_subtitle") : t("grocery_lists.form.new_subtitle")
  end

  def submit_text
    @grocery_list.persisted? ? t("grocery_lists.form.update") : t("grocery_lists.form.create")
  end

  def render_name_field(f)
    form_field(f, :name, label: t("grocery_lists.form.name_label")) do |field|
      f.text_field :name,
                   class: "input is-medium",
                   placeholder: t("grocery_lists.form.name_placeholder"),
                   autofocus: true,
                   required: required_attribute?(@grocery_list, :name), aria: field.aria
    end
  end
end
