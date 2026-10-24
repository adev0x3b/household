# frozen_string_literal: true

# The pipeline on GitHub, in a frame of its own so that GitHub's refusal is
# one line here rather than a broken page. It reloads while a run is live.
class Views::Admin::Deliveries::Console < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "deployment-console"
  INTERVAL = 15_000 # ms between polls while something runs

  # pipeline: nil when GitHub couldn't be asked (error says why);
  # requests: the admin's recent presses (Delivery::Request);
  # token_expiry: a Delivery::TokenExpiry.
  def initialize(pipeline: nil, requests: [], token_expiry: nil, error: nil, active: false)
    @pipeline = pipeline
    @requests = requests
    @token_expiry = token_expiry
    @error = error
    @active = active
  end

  def view_template
    turbo_frame_tag(FRAME_ID, target: "_top") do
      div(class: "report-frame deployment__console", data: { controller: "frame-poll", frame_poll_active_value: @active.to_s, frame_poll_interval_value: INTERVAL,
                                                             frame_poll_url_value: console_admin_delivery_path }) do
        if @error
          p(class: "deployment__error", role: "alert") { t("admin.deployment.console.error", error: @error) }
        else
          notices
          live_runs
          lane(:branch) { card(@pipeline.dev) }
          lane(:main) do
            render Views::Admin::Deliveries::MainCard.new(pipeline: @pipeline)
            div(class: "deployment__environments") { @pipeline.mainline.each { |environment| card(environment) } }
          end
          render Views::Admin::Deliveries::Activity.new(runs: @pipeline.deploy_runs, requests: @requests)
        end
      end
    end
  end

  private

  def notices
    canned_notice if @pipeline.canned?
    frozen_notice if @pipeline.frozen?
    held_notice if held.any?
    expiry_notice if @token_expiry.soon?
  end

  # A lane of the pipeline: a caption, then its cards.
  def lane(key, &)
    section(class: "deployment__lane", aria: { label: t("admin.deployment.lanes.#{key}") }) do
      h2(class: "deployment__lane-title") { t("admin.deployment.lanes.#{key}") }
      yield
    end
  end

  def card(environment) = render(Views::Admin::Deliveries::Cards::Base.for(environment).new(pipeline: @pipeline, environment: environment))

  # This copy answers GitHub from canned files (dev, a development server): a made-up pipeline, presses that go nowhere.
  def canned_notice
    render Components::Notice.new(tone: :neutral) { p { t("admin.deployment.canned") } }
  end

  # Automatic deploys are held: by whom and why, when the note says.
  def frozen_notice
    render Components::Notice.new(tone: :action) do
      p do
        render Components::Icon.new("fa-snowflake")
        whitespace
        plain t("admin.deployment.frozen", note: @pipeline.freeze_note.present? ? t("admin.deployment.frozen_note", note: @pipeline.freeze_note) : "")
      end
    end
  end

  # Main has a migration production can't take while serving: what the
  # rehearsal on production's data said, or that none ran yet.
  def held_notice
    rehearsal = @pipeline.staging.rehearsal(@pipeline.head.sha)
    render Components::Notice.new(tone: :action) do
      p do
        strong { t("admin.deployment.held_notice", version: @pipeline.head.short, count: held.size) }
        whitespace
        plain rehearsal_line(rehearsal)
        whitespace
        a(href: new_admin_delivery_request_path(kind: :release, version: @pipeline.head.sha), data: { turbo_stream: true }) { t("admin.deployment.actions.release_now") }
      end
      ul { held.each { |path| li(class: "report-mono") { path } } }
    end
  end

  def rehearsal_line(rehearsal)
    if rehearsal.nil?
      t("admin.deployment.rehearsal.none")
    elsif rehearsal.succeeded?
      t("admin.deployment.rehearsal.passed", migration: seconds(rehearsal.migration_seconds), downtime: seconds(rehearsal.downtime_seconds))
    else
      t("admin.deployment.rehearsal.undone", reason: rehearsal.description.delete_prefix("undone:").strip)
    end
  end

  def expiry_notice
    expired = @token_expiry.expired?
    render Components::Notice.new(tone: expired ? :critical : :action) do
      p do
        plain expired ? t("admin.deployment.token_expired") : t("admin.deployment.token_expiring", count: @token_expiry.days_left)
        whitespace
        a(href: admin_settings_path) { t("admin.deployment.no_token_link") }
      end
    end
  end

  def live_runs
    @pipeline.live_runs.each { |run| render Views::Admin::Deliveries::RunCard.new(run: run, jobs: @pipeline.jobs(run)) }
  end

  def held = (@held ||= @pipeline.held(@pipeline.production))

  def seconds(value) = t("admin.deployment.seconds", count: value.to_i)
end
