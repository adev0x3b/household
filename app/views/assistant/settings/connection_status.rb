# frozen_string_literal: true

# Whether the assistant can reach its model. The settings page loads it
# lazily, so an offline server never slows the page down; the first setup
# shows it only once the Test press has an answer.
class Views::Assistant::Settings::ConnectionStatus < Views::Base
  include Phlex::Rails::Helpers::TurboFrameTag

  FRAME_ID = "assistant-settings-connection"

  # ok is nil until there is an answer: still checking with a src, not yet
  # tested without one.
  def initialize(ok: nil, provider: nil, model: nil, tested: false, reason: nil, src: nil)
    @ok = ok
    @provider = provider
    @model = model
    @tested = tested
    @reason = reason
    @src = src
  end

  def view_template
    turbo_frame_tag(FRAME_ID, src: @src, loading: (:lazy if @src)) do
      div(class: "assistant-settings__connection", aria: { live: "polite" }) do
        if @ok.nil? && @src
          span(class: "report-hint") do
            render Components::Icon.new("fa-spinner fa-spin")
            whitespace
            plain t("assistant.settings.connection.checking")
          end
        elsif @ok.nil?
          span(class: "report-hint") { t("assistant.settings.connection.untested") }
        else
          render Components::StatusBadge.new(tone: @ok ? :good : :critical, icon: @ok ? "fa-plug-circle-check" : "fa-plug-circle-xmark",
                                             label: t("assistant.settings.connection.#{@ok ? "ok" : "unreachable"}"))
          span(class: "report-hint") { detail }
        end
      end
    end
  end

  private

  def detail
    text = @ok ? t("assistant.settings.connection.ok_detail", provider: t("assistant.settings.providers.#{@provider}.name"), model: @model) : @reason
    @tested ? "#{text} · #{t("assistant.settings.connection.tested")}" : text
  end
end
