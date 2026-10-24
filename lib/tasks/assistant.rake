# frozen_string_literal: true

# Debugging the assistant from the terminal (see "Debugging" in docs/architecture/assistant.md).
namespace :assistant do
  desc "Print a chat turn by turn: user text, every tool call with arguments and result, replies, tokens"
  task :trace, [ :chat_id ] => :environment do |_, args|
    chat = args[:chat_id] ? Assistant::Chat.find(args[:chat_id]) : Assistant::Chat.order(:updated_at).last
    abort "No assistant chats yet." unless chat

    puts Assistant::Trace.new(chat).to_text
  end

  desc 'Run turns against the configured model and roll everything back: assistant:try["first|second|@2026-09-25 third"]'
  task :try, [ :messages ] => :environment do |_, args|
    # Rake splits arguments on commas; put them back together. Rake can't take
    # newlines or backslashes in an argument: use MESSAGES="…" for multi-line text.
    turns = AssistantEval::Try.turns_from(ENV["MESSAGES"].presence || ([ args[:messages] ] + args.extras).compact.join(","))
    abort 'Usage: bin/rails "assistant:try[message|message|@YYYY-MM-DD message]" (or MESSAGES="…") [PROFILE=username | FRESH=1] [TODAY=YYYY-MM-DD] [LOCALE=it]' if turns.empty?

    $stdout.sync = true
    AssistantEval::Try.new(turns: turns, profile: ENV["PROFILE"], fresh: ENV["FRESH"].present?, locale: ENV.fetch("LOCALE", "en"),
                           today: ENV["TODAY"].presence).call
  rescue AssistantEval::Try::Busy => e
    abort e.message
  end
end
