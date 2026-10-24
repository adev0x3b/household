# frozen_string_literal: true

require "etc"
require "open3"
require "shellwords"

module Provision
  # Every command the wizard runs goes through here — streamed to the
  # terminal, or captured — so the tests see each one and answer it
  # (ProvisionFakes::Shell). Run as yourself, it asks for sudo where a step
  # needs it; run under sudo, "me" is still the person at the keyboard
  # (SUDO_USER), who owns the keys and the files.
  class Shell
    class Failed < StandardError; end

    attr_reader :me, :out

    def initialize(out: $stdout, err: $stderr, me: nil)
      @out = out
      @err = err
      @me = me || ENV["SUDO_USER"].to_s.then { _1.empty? ? Etc.getlogin : _1 }
    end

    def root? = Process.uid.zero?
    def my_home = Etc.getpwnam(me).dir

    # Runs a command, its output on the terminal — or into a file (out:).
    # A failure raises, unless allowed (then false). stdin: text given to
    # it, never on the command line.
    def run(*argv, sudo: false, as_me: false, stdin: nil, out: nil, allow_failure: false)
      command = wrap(argv, sudo: sudo, as_me: as_me)
      status = if out
        File.open(out, "wb") { |file| Open3.popen2(*command) { |input, output, waiter| input.close; IO.copy_stream(output, file); waiter.value } }
      elsif stdin
        Open3.popen2(*command) { |input, output, waiter| input.write(stdin); input.close; IO.copy_stream(output, @out); waiter.value }
      else
        pid = Process.spawn(*command, out: @out.respond_to?(:fileno) ? @out : $stdout, err: @err.respond_to?(:fileno) ? @err : $stderr)
        Process.wait2(pid).last
      end
      return true if status.success?
      raise Failed, "#{argv.first} failed (#{status.exitstatus})" unless allow_failure

      false
    end

    # Runs a command and gives back what it printed, stripped. A failure
    # raises, unless allowed (then nil).
    def capture(*argv, sudo: false, as_me: false, stdin: nil, allow_failure: false)
      output, status = Open3.capture2e(*wrap(argv, sudo: sudo, as_me: as_me), stdin_data: stdin)
      return output.strip if status.success?
      raise Failed, "#{argv.first} failed (#{status.exitstatus}): #{output.strip}" unless allow_failure

      nil
    end

    def ok?(*argv, **options) = !capture(*argv, allow_failure: true, **options).nil?

    # A section's heading, a line, a warning: what the bash script printed.
    def say(heading) = @out.puts("\n\e[1m== #{heading}\e[0m")
    def tell(line) = @out.puts(line)
    def warn(line) = @err.puts("warning: #{line}")

    private

    # sudo where asked (unless root already); as me where asked while root.
    def wrap(argv, sudo:, as_me:)
      argv = argv.map(&:to_s)
      return [ "sudo", *argv ] if sudo && !root?
      return [ "sudo", "-u", me, "-H", *argv ] if as_me && root?

      argv
    end
  end
end
