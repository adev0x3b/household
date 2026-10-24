# frozen_string_literal: true

module Assistant
  # How many messages a household can still send the assistant today: the
  # installation's ASSISTANT_MESSAGES_PER_DAY (Platform.assistant_messages_per_day),
  # shared by its members and counted from what they sent since midnight.
  # Unlimited where the installation sets none.
  #
  #   allowance = Assistant::MessageAllowance.new(household)
  #   allowance.left        # => 12, or nil: no limit
  #   allowance.any_left?
  class MessageAllowance
    def initialize(household)
      @household = household
    end

    def max = Platform.assistant_messages_per_day

    def left
      return if max.nil?

      [ max - sent_today, 0 ].max
    end

    # The messages are counted once, however the answer is read.
    def any_left?
      remaining = left
      remaining.nil? || remaining.positive?
    end

    private

    def sent_today
      Message.where(role: "user", created_at: Time.current.all_day)
        .where(assistant_chat_id: Chat.where(profile_id: @household.profiles.select(:id)).select(:id)).count
    end
  end
end
