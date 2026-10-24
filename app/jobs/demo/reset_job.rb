# frozen_string_literal: true

# Rebuilds the demo household every night on the demo installation
# (config/recurring.yml, where KAMAL_DESTINATION is demo): whatever visitors
# did is gone and its six months end today again. Nothing happens where
# there is no demo household: creating the first one is a decision
# (`bin/rails demo:seed`), not something a schedule does.
#
# The seeder runs in a process of its own: it sets the clock to each day it
# lives through (Demo::Seeder), and a clock moved inside the job worker
# would be wrong for every other job running there in the meantime.
class Demo::ResetJob < ApplicationJob
  runs_outside_web_server

  def perform
    return unless Demo::Seeder.household

    self.class.seed! or raise "the demo household could not be rebuilt (bin/rails demo:seed failed)"
  end

  def self.seed!
    system({ "RAILS_ENV" => Rails.env }, RbConfig.ruby, "bin/rails", "demo:seed", chdir: Rails.root.to_s, out: File::NULL)
  end
end
