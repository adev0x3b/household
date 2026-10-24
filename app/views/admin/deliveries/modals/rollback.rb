# frozen_string_literal: true

# Production back to a version it ran before: the candidates to pick from,
# each with its commit and when it was deployed; picking one changes the
# phrase to type back.
class Views::Admin::Deliveries::Modals::Rollback < Views::Admin::Deliveries::Modals::Base
  private

  def body(_form)
    candidates = @press.candidates
    if candidates.empty?
      hint { t("admin.deployment.modals.rollback.none") }
      return
    end

    fieldset(class: "field") do
      legend(class: "label") { t("admin.deployment.modals.rollback.pick") }
      div(class: "report-choices") { candidates.each { |record| candidate(record) } }
    end
    hint { t("admin.deployment.modals.rollback.help") }
  end

  def candidate(record)
    label(class: "report-choice") do
      input(type: "radio", name: "press[version]", value: record.sha, checked: record.sha == @press.version,
            data: { phrase: record.short, action: "change->typed-confirm#pick" })
      span(class: "report-choice__text") do
        span(class: "report-mono") { record.short }
        whitespace
        plain @press.pipeline.commit(record.sha).title
        span(class: "deployment-modal__meta") { t("admin.deployment.modals.rollback.deployed", time: time_ago_in_words(record.finished_at || record.created_at)) }
      end
    end
  end
end
