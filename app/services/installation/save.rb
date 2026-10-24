# frozen_string_literal: true

module Installation
  # Saves sections of the installation's settings together (the settings
  # page's cards): all of them, or nothing when one is wrong, each section
  # then carrying its errors.
  #
  #   result = Installation::Save.call([ allowances, books ], by: current_profile)
  #   result.success?   # false (error :invalid): the sections say what was wrong
  class Save
    Result = ServiceResult.define(:setting)

    def self.call(sections, by:)
      # Every section is checked, not only up to the first wrong one, so each shows its errors.
      return Result.new(setting: nil, error: :invalid) unless sections.map(&:valid?).all?

      setting = Platform::Setting.first_or_start
      sections.each { |section| section.apply_to(setting) }
      setting.updated_by = by
      setting.save!
      Result.new(setting: setting, error: nil)
    end
  end
end
