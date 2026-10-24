# frozen_string_literal: true

require "stringio"

# bin/provision's parts without a machine: a shell that records every
# command and answers from a script, and a prompt fed its answers.
module ProvisionFakes
  class Shell < Provision::Shell
    Call = Data.define(:argv, :options)

    attr_reader :calls

    def initialize(answers: {}, me: "adev", root: false, home: "/home/adev")
      super(out: StringIO.new, err: StringIO.new, me: me)
      @answers = answers
      @root = root
      @home = home
      @calls = []
    end

    def root? = @root
    def my_home = @home

    # answers: a pattern on the command line → what it prints, or :fail, or
    # a lambda given the argv. Unlisted commands succeed, printing nothing.
    def run(*argv, sudo: false, as_me: false, stdin: nil, out: nil, allow_failure: false)
      record(argv, sudo:, as_me:, stdin:, out:)
      answer = answer_for(argv)
      return true unless answer == :fail
      raise Provision::Shell::Failed, "#{argv.join(" ")} failed" unless allow_failure

      false
    end

    def capture(*argv, sudo: false, as_me: false, stdin: nil, allow_failure: false)
      record(argv, sudo:, as_me:, stdin:)
      answer = answer_for(argv)
      return answer.to_s unless answer == :fail
      raise Provision::Shell::Failed, "#{argv.join(" ")} failed" unless allow_failure

      nil
    end

    def ran?(pattern) = calls.any? { _1.argv.join(" ").match?(pattern) }
    def commands = calls.map { _1.argv.join(" ") }
    def printed = out.string
    def warnings = @err.string

    private

    def record(argv, **options) = calls << Call.new(argv: argv.map(&:to_s), options: options)

    def answer_for(argv)
      line = argv.join(" ")
      _, answer = @answers.find { |pattern, _| line.match?(pattern) }
      answer.respond_to?(:call) ? answer.call(argv) : answer
    end
  end

  # The answers typed, in order; a missing one is the default.
  def prompt_with(*answers, assume_defaults: false)
    Provision::Prompt.new(input: StringIO.new(answers.map { "#{_1}\n" }.join), output: StringIO.new, assume_defaults: assume_defaults)
  end
end

module ProvisionFakes
  # What a pipeline's machine answers, every step in place: sshd, Tailscale,
  # gh with admin, environments, the deploy user, a host key, a runner.
  def machine_answers(keys: [], secrets: %w[DEPLOY_SSH_KEY], installed: {})
    {
      /\Adocker --version/ => "Docker version 27.0",
      /\Aid -nG / => "adev docker",
      /\Asystemctl is-active --quiet ssh\z/ => "",
      /\Atailscale status --json/ => '{"Self": {"DNSName": "box.example."}}',
      /\Atailscale ip -4/ => "100.64.0.9",
      /\Agh auth status/ => "",
      %r{\Agh api repos/owner/household --jq .permissions.admin} => "true",
      %r{\Agh api --method PUT repos/owner/household/environments/} => "{}",
      %r{deployment-branch-policies --jq} => "branch:main",
      /\Aid deploy/ => "",
      /\Agetent passwd deploy/ => "deploy:x:1001:1001::/home/deploy:/bin/bash",
      %r{\Acat /home/deploy/.ssh/authorized_keys} => keys.join("\n"),
      /\Agh secret list --repo owner\/household --env \S+ --json name/ => secrets.join("\n"),
      /\Assh-keygen -q -t ed25519/ => ->(argv) { path = argv[argv.index("-f") + 1]; File.write(path, "PRIVATE KEY\n"); File.write("#{path}.pub", "ssh-ed25519 AAAAci household-ci\n"); "" },
      %r{\Acat /etc/ssh/ssh_host_ed25519_key.pub} => "ssh-ed25519 AAAAhost root@box",
      /\Assh-keygen -F / => :fail,
      /\Ainstall -m 600 -o deploy -g deploy / => ->(argv) { installed[:authorized_keys] = File.read(argv[-2]); "" },
      %r{\Agh api --method PUT repos/owner/household/actions/permissions} => "{}"
    }
  end

  def pipeline_root(dir, demo: true)
    root = File.join(dir, "checkout")
    FileUtils.mkdir_p(File.join(root, ".kamal"))
    FileUtils.mkdir_p(File.join(root, "bin"))
    File.write(File.join(root, ".kamal", "env.example"), "# What config/deploy.yml needs.\n")
    File.write(File.join(root, ".kamal", "env"), <<~ENV)
      DEPLOY_HOST=box.example
      KAMAL_REGISTRY_USERNAME=owner
      GITHUB_REPOSITORY=owner/household
      PRODUCTION_HOST=example.com
      STAGING_HOST=staging.example.com
      DEV_HOST=dev.example.com
      #{"DEMO_HOST=demo.example.com" if demo}
      TIME_ZONE=Europe/Rome
    ENV
    root
  end
end
