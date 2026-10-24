# frozen_string_literal: true

# The branch dev runs into main: its pull request, whether CI passed on
# its head, the commits main gains, and a warning when dev ran an older
# commit than the one that merges.
class Views::Admin::Deliveries::Modals::Merge < Views::Admin::Deliveries::Modals::Base
  private

  def words = super.merge(number: pull_request&.number, branch: dev.branch)

  # Nil when the branch has none; read once (`cached` keeps no nil).
  def pull_request
    return @pull_request if defined?(@pull_request)

    @pull_request = @pipeline.pull_request(dev)
  end

  def body(_form)
    pull = pull_request
    if pull.nil?
      hint { t("admin.deployment.modals.merge.no_pull_request", branch: some_branch) }
      return
    end

    line do
      a(href: pull.html_url, target: "_blank", rel: "noopener noreferrer") { "##{pull.number}" }
      whitespace
      plain t("admin.deployment.modals.merge.pr_line", title: pull.title, author: pull.author, branch: pull.head_branch)
    end
    line { render Views::Admin::Deliveries::MergeBadge.new(state: @press.state) }
    untested(pull) if @pipeline.untested_on_dev?(dev)
    ships(@pipeline.merge_pending(dev))
    line do
      render Components::Icon.new("fa-arrow-right")
      whitespace
      plain t("admin.deployment.modals.merge.after")
    end
  end

  def untested(pull)
    render Components::Notice.new(tone: :action) do
      p do
        plain t("admin.deployment.modals.merge.untested", ran: dev.short_version, head: pull.head_sha.first(7), count: @pipeline.behind_by(dev))
        whitespace
        a(href: new_admin_delivery_request_path(kind: :preview), data: { turbo_stream: true }) { t("admin.deployment.modals.merge.preview_again") }
      end
    end
  end
end
