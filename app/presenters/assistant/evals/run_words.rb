# frozen_string_literal: true

# What an eval run's row, its status card and its model's card all say about
# it: the model it ran on, how long it has taken, how far along it is, and
# its score with the interval around it.
class Assistant::Evals::RunWords
  include ActionView::Helpers::DateHelper

  # A share of scored scenarios, a fraction from 0 to 1, as "72%".
  def self.percent(fraction) = Statistics::Format.value(fraction && (fraction * 100), :percent)

  def initialize(run)
    @run = run
  end

  def provider = I18n.t("assistant.settings.providers.#{@run.provider}.name", default: @run.provider.to_s)

  def model_line = I18n.t("assistant.evals.run.model_on_provider", model: @run.model, provider: provider)

  # A run still going counts from its start; a finished one, start to end.
  def timing
    return unless @run.started_at
    return I18n.t("assistant.evals.run.running_for", time: time_ago_in_words(@run.started_at)) if @run.active?
    return unless @run.updated_at

    I18n.t("assistant.evals.run.took", time: distance_of_time_in_words(@run.started_at, @run.updated_at))
  end

  # A run resumed past its planned total counts what it did, not what it planned.
  def progress = I18n.t("assistant.evals.run.progress", done: @run.done, total: [ @run.total, @run.done ].max)

  def scored? = !@run.pass_rate.nil?

  def rate = self.class.percent(@run.pass_rate&.first)
  def low = self.class.percent(@run.pass_rate&.second)
  def high = self.class.percent(@run.pass_rate&.third)
end
