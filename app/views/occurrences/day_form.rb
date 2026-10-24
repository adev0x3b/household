# frozen_string_literal: true

# The form of a day of a series (an Occurrence, saved or projected): the
# generic form (Components::Form), posting under its kind's key
# (`task[...]`), and what the viewer may do with the day adds
# (Occurrences::Access): read-only where they may only see it; "Sam will
# be asked to OK this" where the owner must approve; for a new series,
# whose calendar it goes on when a partner lets them add there; for a day
# of a recurring series, whether a change is that day's or the whole
# series'.
class Views::Occurrences::DayForm < Components::Form
  # What a change to a day of a recurring series is for, the day first.
  APPLY_TO_CHOICES = %w[day series].freeze

  # A day of a series that exists is sent to the day's own address, whether
  # the day is saved yet or not; only a new series is posted to its kind.
  # viewer: the Profile filling the form in, or nil when nobody is signed in.
  def initialize(record:, viewer:, **)
    super(record: record, scope: record.event.class.model_name.param_key.to_sym, method: record.event.persisted? ? :patch : :post, **)
    @viewer = viewer
    @access = Occurrences::Access.new(record, viewer)
  end

  private

  # Whether a change is the day's or the series' decides what Save does,
  # so it comes first, above the fields it governs.
  def before_fields
    render_series_version
    render_link_notice
    render_owner_select
    render_apply_to
  end

  def submit_label = asked_owner ? t("links.approvals.form.submit", name: asked_owner.display_name) : super

  def stimulus_data = apply_to? ? { controller: "apply-to", action: "change->apply-to#sync" } : {}

  def new_series? = @record.event.new_record?

  def access_query
    return :create? if new_series?

    @record.persisted? ? :update? : :edit?
  end

  # Nobody signed in reads nothing as read-only: the form is then drawn
  # for a page that asks no one, and every field stays open.
  def read_only?
    return @read_only if defined?(@read_only)

    @read_only = @access.viewer? && !@access.allows?(access_query)
  end

  def asked_owner
    return @asked_owner if defined?(@asked_owner)

    @asked_owner = (@record.event.profile if !read_only? && @access.asks?(access_query))
  end

  def creatable_owners = @creatable_owners ||= @access.creatable_owners

  # The day goes back with its own version (Components::Form) and with its
  # series', since the form shows the series' values where the day has
  # none of its own.
  def render_series_version
    return if new_series?

    input(type: "hidden", name: "#{@scope}[series_lock_version]", value: @record.event.lock_version)
  end

  def render_link_notice
    if read_only?
      render(Components::Notice.new) { p { t("links.approvals.form.readonly", name: @record.event.profile.display_name) } }
    elsif asked_owner
      render(Components::Notice.new(tone: :action)) { p { t("links.approvals.form.notice", name: asked_owner.display_name) } }
    end
  end

  def render_owner_select
    return if creatable_owners.size < 2

    chosen = @record.event.profile_id || @viewer.id
    render Components::Field.new(label: t("links.approvals.form.owner_label"), control_id: "owner_id", select: true) do
      select(name: "owner_id", id: "owner_id") do
        creatable_owners.each do |owner|
          option(value: owner.id, selected: owner.id == chosen) do
            owner == @viewer ? t("links.approvals.form.owner_self") : owner.display_name
          end
        end
      end
    end
  end

  # A day of a recurring series: does what is changed go to this day alone
  # (the default) or to every day of the series (Occurrences::FormSave)?
  def apply_to? = @access.viewer? && !new_series? && @record.event.recurring? && !read_only?

  def render_apply_to
    return unless apply_to?

    render Components::Field.new(label: t("form.apply_to.label"), control_id: "#{@scope}_apply_to", select: true,
                                 class: "form-apply-to", help: t("form.apply_to.help")) do
      select(name: "#{@scope}[apply_to]", id: "#{@scope}_apply_to", data: { apply_to_target: "choice" }) do
        APPLY_TO_CHOICES.each do |choice|
          option(value: choice, selected: choice == "day") { t("form.apply_to.#{choice}") }
        end
      end
    end
  end
end
