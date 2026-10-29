# frozen_string_literal: true

# /admin/emails — the mail this copy sends (Emails::Overview): whether it
# goes out and what stops it otherwise, what went against the budgets,
# what waits and what couldn't go out. The relay and the budgets are set
# on /admin/settings; the test mail is Admin::TestMailsController's.
class Admin::EmailsController < Admin::BaseController
  def index
    render_page Views::Admin::Emails::Index.new(overview: Emails::Overview.new)
  end
end
