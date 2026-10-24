# frozen_string_literal: true

# The strip under the navbar for whoever is in as one of the installation's
# open accounts (the demo's): says where you are, and lets you look at the
# household as each of them (DemosController). One line, a fixed height
# (--demo-banner-height), so full-height pages like the assistant's can
# make room for it.
class Views::Layouts::DemoBanner < Views::Base
  include Phlex::Rails::Helpers::ButtonTo

  # people: the open accounts, in the order the installation lists them.
  def initialize(profile:, people:)
    @profile = profile
    @people = people
  end

  def view_template
    div(class: "demo-banner", role: "note", title: t("demo.welcome")) do
      span(class: "demo-banner__text") do
        render Components::Icon.new("fa-flask")
        # The whole sentence where it fits on one line, a word where it
        # doesn't (a phone); the title and the welcome toast say the rest.
        span(class: "demo-banner__long") { " #{t("demo.banner.text")}" }
        span(class: "demo-banner__short") { " #{t("demo.banner.short")}" }
      end
      div(class: "demo-banner__personas", role: "group", aria: { label: t("demo.banner.see_as") }) do
        @people.each { |person| persona(person) }
      end
    end
  end

  private

  def persona(person)
    current = person == @profile
    name = person.display_name
    # A full page load, as signing in is: the page starts over as them.
    button_to(name, demo_path, params: { as: person.username }, form: { data: { turbo: false } }, form_class: "demo-banner__form",
                               class: "demo-banner__persona#{" is-current" if current}",
                               aria: { current: ("true" if current), label: t("demo.banner.see_as_name", name: name) })
  end
end
