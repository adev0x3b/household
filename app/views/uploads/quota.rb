# frozen_string_literal: true

# How much of the household's storage its files take: "1.2 GB of 50 GB
# used", as a bar.
class Views::Uploads::Quota < Views::Base
  def initialize(quota:)
    @quota = quota
  end

  def view_template
    text = t("uploads.index.quota", used: size(@quota.used), quota: size(@quota.total))

    div(class: "uploads__quota") do
      p(class: "uploads__quota-text") { text }
      render Components::ProgressBar.new(value: @quota.used, max: @quota.total, label: text)
    end
  end

  private

  def size(bytes) = ActiveSupport::NumberHelper.number_to_human_size(bytes, locale: I18n.locale)
end
