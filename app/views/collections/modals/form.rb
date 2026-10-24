# frozen_string_literal: true

# A collection's name and notes, and its status once it exists, worded by
# its section (a therapy in Healthcare).
class Views::Collections::Modals::Form < Views::Base
  def initialize(collection:, url:)
    @collection = collection
    @url = url
  end

  def view_template
    render Components::Modal.new(size: :medium, section: @collection.section) do |modal|
      modal.modal_header(
        title: wording(@collection.persisted? ? :edit_title : :new_title),
        subtitle: (wording(:new_subtitle) unless @collection.persisted?),
        icon: "fa-folder-open"
      )

      render Components::Form.new(
        record: @collection,
        url: @url,
        submit_text: @collection.persisted? ? t("collections.form.update") : wording(:create),
        modal: modal
      ) do |f|
        f.hidden_field :section unless @collection.persisted?
        render_name_field(f)
        render_notes_field(f)
        render_status_field(f) if @collection.persisted?
      end
    end
  end

  private

  def wording(key) = t("collections.sections.#{@collection.section}.form.#{key}")

  def render_name_field(f)
    form_field(f, :name, label: t("collections.form.name_label")) do |field|
      f.text_field :name,
                   class: "input is-medium",
                   placeholder: wording(:name_placeholder),
                   autofocus: true,
                   required: required_attribute?(@collection, :name), aria: field.aria
    end
  end

  def render_notes_field(f)
    form_field(f, :notes, label: t("collections.form.notes_label")) do |field|
      f.text_area :notes,
                  class: "textarea",
                  placeholder: wording(:notes_placeholder),
                  required: required_attribute?(@collection, :notes), aria: field.aria
    end
  end

  def render_status_field(f)
    form_field(f, :status, label: t("collections.form.status_label"), select: true) do |field|
      f.select :status, status_options, {}, required: required_attribute?(@collection, :status), aria: field.aria
    end
  end

  def status_options
    select_options(Collection.statuses.keys) { |key| t("collections.status.#{key}") }
  end
end
