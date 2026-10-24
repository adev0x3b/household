# frozen_string_literal: true

# A linked housemate's action that the item's owner must OK first (their
# LinkGrant says "ask"; EventAuthorizable#needs_approval?) is held, not
# done: call right after `authorize`, before anything is written.
#
#   authorize @occurrence
#   return if held_for_approval?(@occurrence, :update?, kind: :update, form: form)
#
# A form is checked first (its errors shown as on a save, by the
# controller's #shown_again, which OccurrenceForms has) and its changes
# kept (Occurrences::FormSave#payload); the asker's own reminders are saved
# now. Then the modal closes with "Asked Sam to OK it".
module LinkApprovable
  extend ActiveSupport::Concern

  private

  def held_for_approval?(record, query, kind:, form: nil, scope: nil)
    return false unless policy(record).needs_approval?(query)

    if form && !form.valid_for_hold?
      shown_again(form.record)
      return true
    end

    form&.save_reminders!
    approval = Links::Approvals::Hold.call(requester: current_profile, record: record, kind: kind, scope: scope,
                                           payload: form&.payload || {}, preview: form&.preview || [])
    render turbo_stream: [ close_modal, toast(:notice, t("links.notices.asked", name: approval.owner.display_name)) ]
    true
  end
end
