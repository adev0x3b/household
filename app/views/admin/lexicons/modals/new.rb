# frozen_string_literal: true

# Adding a language: pick it from kaikki.org's list (type to search — a
# datalist, no script) and say which word of a name is the noun. Its code is
# read from the extract on save; the import starts at once.
class Views::Admin::Lexicons::Modals::New < Views::Base
  include Phlex::Rails::Helpers::NumberWithDelimiter

  def initialize(language:, catalog:)
    @language = language
    @catalog = catalog
  end

  def view_template
    render Components::Modal.new(size: :medium) do |modal|
      modal.modal_header(title: t("admin.lexicons.add.title"), icon: "fa-language")
      render Components::Form.new(record: @language, url: admin_lexicons_path, submit_text: t("admin.lexicons.add.submit"), modal: modal) do |f|
        name_field(f)
        head_field(f)
        p(class: "help") { t("admin.lexicons.add.what_happens") }
      end
    end
  end

  private

  def name_field(f)
    render Components::Field.new(label: t("admin.lexicons.add.name_label"), control_id: f.field_id(:wiktionary), help: name_help) do
      f.text_field :wiktionary, class: "input is-medium", list: "lexicon-catalog", autocomplete: "off", required: true, autofocus: true,
                                placeholder: t("admin.lexicons.add.name_placeholder")
      datalist(id: "lexicon-catalog") do
        @catalog.each { |entry| option(value: entry.name) { senses(entry) } }
      end
    end
  end

  def name_help
    @catalog.any? ? t("admin.lexicons.add.name_help", count: @catalog.size) : t("admin.lexicons.add.no_catalog")
  end

  def senses(entry) = t("admin.lexicons.add.senses", count: entry.senses, formatted: number_with_delimiter(entry.senses))

  def head_field(f)
    render Components::Field.new(label: t("admin.lexicons.add.head_label"), control_id: f.field_id(:head),
                                 help: t("admin.lexicons.add.head_help")) do
      div(class: "select is-medium") do
        f.select :head, Lexicon::Config::HEADS.map { [ t("admin.lexicons.add.heads.#{_1}"), _1 ] }, {}, required: true
      end
    end
  end
end
