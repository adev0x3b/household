# frozen_string_literal: true

# A card's line on whose a shared thing is. Its owner reads who else has it,
# and nothing while nobody does; a housemate reads whose it is.
#
#   render Views::Shares::Whose.new(thing: recipe, viewer: current_profile)
class Views::Shares::Whose < Views::Base
  def initialize(thing:, viewer:)
    @thing = thing
    @viewer = viewer
  end

  def view_template
    if @thing.profile_id != @viewer.id
      line("fa-user", t("shares.owner", name: @thing.profile.display_name))
    elsif @thing.shared_profiles.any?
      line("fa-user-group", t("shares.shared_with_names", names: Views::Shares::List.names(@thing.shared_profiles)))
    end
  end

  private

  def line(icon, text)
    p(class: "share-whose") do
      render Components::Icon.new(icon)
      span { text }
    end
  end
end
