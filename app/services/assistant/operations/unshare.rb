# frozen_string_literal: true

module Assistant
  module Operations
    # Stops sharing something with a household member. Nothing of the
    # user's is shown to anyone, so it is saved at once.
    class Unshare < Share
      def risky? = false

      private

      def check_sharing(shared)
        fail!("it isn't shared with #{person}") unless shared
      end

      def write!
        share = ::Shares::Destroy.call(shares.find_by!(profile_id: @member.id), by: profile)
        [ { "kind" => "unshared", "model" => share.class.name, "attributes" => share.slice(share.class.thing_key.to_s, "profile_id") } ]
      end
    end
  end
end
