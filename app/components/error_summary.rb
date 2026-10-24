# frozen_string_literal: true

# Why a form didn't save, above its fields: inside a modal (Components::Form)
# and on the pages before sign-in. It stays until the form is sent again,
# so there is time to fix every line, and it is an alert, so a screen
# reader says it when the form comes back.
class Components::ErrorSummary < Components::Base
  def initialize(record:)
    @record = record
  end

  def render? = @record.errors.any?

  def view_template
    render Components::Notice.new(tone: :critical) do
      p { t("form.errors.intro") }
      ul { Forms::Errors.new(@record).sentences.each { |sentence| li { sentence } } }
    end
  end
end
