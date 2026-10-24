# frozen_string_literal: true

# What the assistant costs, per household, over a period: messages sent,
# tokens in and out, and money when the provider's prices are known
# (RubyLLM fills the cost columns for cloud models; Ollama costs nothing).
# Read from RubyLLM's usage rows, one per model step, and the messages
# people sent.
#
#   Assistant::Usage.by_household(Time.current.all_month)   # => [Row, …], most tokens first
#   Assistant::Usage.for(household, 30.days.ago..)           # => Row (zeros when it never asked)
module Assistant
  class Usage
    Row = Data.define(:household, :messages, :input_tokens, :output_tokens, :cost) do
      def tokens = input_tokens + output_tokens
      def cost? = cost.to_d.positive?
    end

    def self.by_household(period = Time.current.all_month)
      tokens = tokens_by_household(period)
      messages = Assistant::Message.where(role: "user", hidden: false, created_at: period)
        .joins(assistant_chat: :profile).group("profiles.household_id").count
      Household.where(id: tokens.keys | messages.keys).map do |household|
        input, output, cost = tokens.fetch(household.id, [ 0, 0, 0 ])
        Row.new(household: household, messages: messages.fetch(household.id, 0), input_tokens: input, output_tokens: output, cost: cost.to_d)
      end.sort_by { |row| [ -row.tokens, -row.messages, row.household.name ] }
    end

    def self.for(household, period = Time.current.all_month)
      by_household(period).find { |row| row.household == household } ||
        Row.new(household: household, messages: 0, input_tokens: 0, output_tokens: 0, cost: 0.to_d)
    end

    # { household_id => [input tokens, output tokens, cost] }. A usage row
    # names its chat polymorphically, which no association joins through,
    # so the steps are summed per chat and the chats' households read next.
    def self.tokens_by_household(period)
      by_chat = RubyLLM::ActiveRecord::Usage.where(chat_type: "Assistant::Chat", created_at: period).group(:chat_id)
        .pluck(:chat_id, Arel.sql("SUM(input_tokens)"), Arel.sql("SUM(output_tokens)"), Arel.sql("SUM(total_cost)"))
      household_of = Assistant::Chat.joins(:profile).where(id: by_chat.map(&:first)).pluck(:id, "profiles.household_id").to_h
      by_chat.each_with_object({}) do |(chat_id, input, output, cost), totals|
        total = totals[household_of.fetch(chat_id)] ||= [ 0, 0, 0.to_d ]
        total[0] += input.to_i
        total[1] += output.to_i
        total[2] += cost.to_d
      end
    end
    private_class_method :tokens_by_household
  end
end
