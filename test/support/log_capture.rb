# frozen_string_literal: true

# What the app wrote to its log while the block ran, at the level production
# logs at, so a test can hold what an admin reading the log would see.
module LogCapture
  def logged(level: :info)
    io = StringIO.new
    capture = ActiveSupport::Logger.new(io, level: level)
    Rails.logger.broadcast_to(capture)
    begin
      yield
    ensure
      Rails.logger.stop_broadcasting_to(capture)
    end
    io.string
  end
end
