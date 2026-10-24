# frozen_string_literal: true

# The units a quantity field suggests as one types (`list: Components::
# UnitsDatalist::ID` on the input): the household's, by name. A name not
# on it is still fine: the form makes the unit (a TypedName).
#
#   render Components::UnitsDatalist.new(profile: @recipe.profile)
class Components::UnitsDatalist < Components::Base
  ID = "units-datalist"

  def initialize(profile:)
    @profile = profile
  end

  def view_template
    datalist(id: ID) { Unit.names_for(@profile).each { |name| option(value: name) } }
  end
end
