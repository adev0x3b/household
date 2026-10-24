# frozen_string_literal: true

# Answers one address in place of the app, with a status and the public page
# for it, so a system test can see what the browser does with a crash or a
# missing answer while the app itself stays as it is. The test server answers
# on its own threads, hence an answer kept on the class.
class StandInAnswers
  @answers = Concurrent::Map.new

  class << self
    def answering(path, status:)
      @answers[path] = status
      yield
    ensure
      @answers.delete(path)
    end

    def status_for(path) = @answers[path]
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    status = self.class.status_for(env["PATH_INFO"])
    return @app.call(env) unless status

    [ status, { "content-type" => "text/html; charset=utf-8" }, [ Rails.public_path.join("#{status}.html").read ] ]
  end
end
