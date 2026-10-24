# frozen_string_literal: true

module Delivery
  class Github < ApplicationClient
    # The repository's Actions variables: the freeze (FREEZE, FREEZE_NOTE).
    module Variables
      # A variable's value, nil when it isn't set.
      def variable(name)
        cached("variable/#{name}", LIVE_TTL) do
          response = perform(get("/actions/variables/#{name}"))
          response.code.to_s == "404" ? nil : json(response)["value"]
        end
      end

      # Creates it, or changes it when it is there already (409).
      def set_variable(name, value)
        response = perform(post("/actions/variables", name: name, value: value.to_s))
        response = perform(patch("/actions/variables/#{name}", name: name, value: value.to_s)) if response.code.to_s == "409"
        json(response)
        forget("variable/#{name}")
        true
      end

      def delete_variable(name)
        response = perform(delete("/actions/variables/#{name}"))
        json(response) unless response.code.to_s == "404"
        forget("variable/#{name}")
        true
      end

      def frozen? = variable(FREEZE) == "true"
    end
  end
end
