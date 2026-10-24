# frozen_string_literal: true

# Letting the automatic deploys go again, with the note the freeze left.
class Views::Admin::Deliveries::Modals::Unfreeze < Views::Admin::Deliveries::Modals::Base
  private

  def body(_form)
    line { t("admin.deployment.modals.unfreeze.line") }
    hint { @pipeline.freeze_note } if @pipeline.freeze_note.present?
  end
end
