# frozen_string_literal: true

# The pipeline, as the console drives it over GitHub from any copy of the
# app. It reads Deployment and never the other way round, so it could one
# day serve another repository's pipeline from a monitor of its own.
module Delivery
end
