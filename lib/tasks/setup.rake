# frozen_string_literal: true

namespace :setup do
  # The code alone goes to standard output and the words around it to
  # standard error, so the installer can capture the code while a person at
  # a terminal reads the line whole. A copy set up already exits with 3, a
  # status of its own: Rake exits with 1 when the task fails. The words are
  # written to standard error directly, since warn prints nothing while
  # Ruby's warnings are off.
  desc "A new one-time code for the setup page, while nobody has signed in yet (it replaces any code before it)"
  task code: :environment do
    result = SetupCodes::Renew.call
    if result.failure?
      $stderr.puts "This copy is set up already: the setup page is gone, and people are invited from the app."
      exit 3
    end

    $stderr.print "Setup code: "
    puts result.code
    $stderr.puts "The setup page asks for it once, and it works until the first account exists."
  end
end
