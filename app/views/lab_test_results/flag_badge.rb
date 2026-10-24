# frozen_string_literal: true

# How a value stood against its reference range, as a pill: in the lab
# result's form beside the value, and on Home's table of analytes.
class Views::LabTestResults::FlagBadge < Views::Base
  LOOKS = {
    normal: Components::StatusLook.new(tone: :good),
    low: Components::StatusLook.new(tone: :warning),
    high: Components::StatusLook.new(tone: :warning),
    abnormal: Components::StatusLook.new(tone: :critical)
  }.freeze

  def initialize(flag:)
    @flag = flag.to_sym
  end

  def view_template
    render LOOKS.fetch(@flag).badge(label: t("lab_test_results.form.entries.flags.#{@flag}"))
  end
end
