# frozen_string_literal: true

# One eval case, by hand: fixing one the model wrote, or creating one for a
# supply of the admin's own — then also its English name and plural (the
# shared supplies the language has no case for yet are suggested). The word
# a speaker would label the supply with, and the two things they'd say with
# it, each with the English sentence it stands for. Saved cases are kept
# when the model writes the cases again.
class Views::Admin::Lexicons::Modals::Case < Views::Base
  # examples: the English sentence each of the case's two stands for, by
  # field. concepts: the shared supplies the language has no case for yet,
  # to suggest on a new case.
  def initialize(kase:, url:, language:, examples:, concepts: [])
    @case = kase
    @url = url
    @language = language
    @examples = examples
    @concepts = concepts
  end

  def view_template
    render Components::Modal.new(size: :medium) do |modal|
      if @case.new_record?
        modal.modal_header(title: t("admin.lexicons.cases.new_title", language: @language.wiktionary), icon: "fa-plus")
      else
        modal.modal_header(title: t("admin.lexicons.cases.edit_title", concept: @case.concept), icon: "fa-pen")
      end
      submit = t("admin.lexicons.cases.#{@case.new_record? ? "add" : "save"}")
      render Components::Form.new(record: @case, url: @url, submit_text: submit, modal: modal) do |f|
        if @case.new_record?
          text(f, :concept, help: t("admin.lexicons.cases.help.concept"), list: "lexicon-concepts")
          concepts_list
          text(f, :english_plural, help: t("admin.lexicons.cases.help.english_plural"), required: false)
        end
        text(f, :native_singular)
        text(f, :native_plural)
        area(f, :dose_sentence, help: t("admin.lexicons.cases.help.dose", language: @language.wiktionary, sentence: @examples.fetch(:dose_sentence)))
        area(f, :purchase_sentence, help: t("admin.lexicons.cases.help.purchase", language: @language.wiktionary,
                                                                                  sentence: @examples.fetch(:purchase_sentence)))
      end
    end
  end

  private

  def concepts_list
    datalist(id: "lexicon-concepts") { @concepts.each { |concept| option(value: concept.concept) } }
  end

  def text(f, field, help: nil, required: true, **options)
    render Components::Field.new(label: t("admin.lexicons.cases.fields.#{field}"), control_id: f.field_id(field), help: help) do
      f.text_field field, class: "input is-medium", required: required, **options
    end
  end

  def area(f, field, help: nil)
    render Components::Field.new(label: t("admin.lexicons.cases.fields.#{field}"), control_id: f.field_id(field), help: help) do
      f.text_area field, class: "textarea", rows: 2, required: true
    end
  end
end
