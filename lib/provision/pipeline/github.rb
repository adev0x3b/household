# frozen_string_literal: true

require "json"

module Provision
  module Pipeline
    # The repository on GitHub, through gh as the person at the keyboard:
    # its environments, variables and secrets (a secret's value always on
    # stdin, never on the command line), the Deploy workflow and its runs,
    # the runners.
    class Github
      attr_reader :repo

      def initialize(shell, repo:)
        @shell = shell
        @repo = repo
      end

      def gh(*argv, stdin: nil, allow_failure: false) = @shell.capture("gh", *argv, as_me: true, stdin: stdin, allow_failure: allow_failure)

      def api(path, method: nil, fields: {}, jq: nil, input: nil, allow_failure: false)
        argv = [ "api", *(method ? [ "--method", method ] : []), "repos/#{repo}/#{path}".chomp("/") ]
        argv += fields.flat_map { |name, value| [ "-f", "#{name}=#{value}" ] }
        argv += [ "--jq", jq ] if jq
        argv += [ "--input", "-" ] if input
        gh(*argv, stdin: input, allow_failure: allow_failure)
      end

      def admin? = api("", jq: ".permissions.admin", allow_failure: true) == "true"

      # The environment made or kept, main alone allowed to use it; false
      # where GitHub offers none (GitHub Free, a private repository).
      def environment!(name)
        policy = '{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}'
        return false if api("environments/#{name}", method: "PUT", input: policy, allow_failure: true).nil?

        policies = api("environments/#{name}/deployment-branch-policies", jq: '.branch_policies[] | "\(.type):\(.name)"', allow_failure: true).to_s.split("\n")
        api("environments/#{name}/deployment-branch-policies", method: "POST", fields: { name: "main", type: "branch" }) unless policies.include?("branch:main")
        others = policies - [ "branch:main" ]
        @shell.warn "#{name} also lets #{others.join(" ")} use its secrets: Settings → Environments → #{name}" if others.any?
        true
      end

      def environment?(name) = !api("environments/#{name}", allow_failure: true).nil?

      def variable_set(name, value, env: nil) = gh("variable", "set", name, "--repo", repo, *env_flag(env), "--body", value)
      def variable_delete(name, env: nil) = gh("variable", "delete", name, "--repo", repo, *env_flag(env), allow_failure: true)

      def variables(env: nil)
        JSON.parse(gh("variable", "list", "--repo", repo, *env_flag(env), "--json", "name,value", allow_failure: true).to_s).to_h { [ _1["name"], _1["value"] ] }
      rescue JSON::ParserError
        {}
      end

      # Where a destination runs, as the Deploy workflow reads it: its
      # environment's DEPLOY_HOST, else the repository's; nil where neither says.
      def deploy_host(destination) = variable_of(destination, "DEPLOY_HOST")

      # The host key the workflow trusts for that machine, the same way.
      def known_host(destination) = variable_of(destination, "DEPLOY_KNOWN_HOSTS")

      def secret_set(name, value, env: nil) = gh("secret", "set", name, "--repo", repo, *env_flag(env), stdin: value)
      def secret_delete(name, env: nil) = gh("secret", "delete", name, "--repo", repo, *env_flag(env), allow_failure: true)
      def secret_names(env: nil) = gh("secret", "list", "--repo", repo, *env_flag(env), "--json", "name", "--jq", ".[].name", allow_failure: true).to_s.split("\n")

      # A run of anyone without write access waits for approval.
      def fork_approval! = !api("actions/permissions/fork-pr-contributor-approval", method: "PUT", fields: { approval_policy: "all_external_contributors" }, allow_failure: true).nil?

      # The newest commit on main that CI passed and built.
      def newest_main_version
        sha = gh("run", "list", "--repo", repo, "--workflow", "ci.yml", "--branch", "main", "--status", "success", "--json", "headSha", "--limit", "1", "--jq", ".[0].headSha", allow_failure: true).to_s
        sha.empty? ? nil : sha
      end

      # Where the jobs run (the RUNS_ON variable): the labels of the household's runner, or nil for GitHub's.
      def runs_on
        value = variables["RUNS_ON"]
        return nil if value.nil? || value.empty?

        labels = JSON.parse(value)
        labels.is_a?(Array) ? labels.map(&:to_s) : nil
      rescue JSON::ParserError
        nil
      end

      # One online runner with every label RUNS_ON names, or GitHub's own.
      def runner_available?
        labels = runs_on or return true
        online = api("actions/runners", jq: '.runners[] | select(.status=="online") | [.labels[].name] | join(",")', allow_failure: true).to_s
        online.split("\n").any? { |have| (labels - have.split(",")).empty? }
      end

      def dispatch(action:, destination:, reason:, version: nil, branch: nil, fresh: false)
        fields = { action: action, destination: destination, reason: reason }
        fields[:version] = version if version
        fields[:branch] = branch if branch
        fields[:fresh] = "true" if fresh
        gh("workflow", "run", "deploy.yml", "--repo", repo, "--ref", "main", *fields.flat_map { |name, value| [ "-f", "#{name}=#{value}" ] })
      end

      def latest_run_id(workflow: "deploy.yml")
        id = gh("run", "list", "--repo", repo, "--workflow", workflow, "--limit", "1", "--json", "databaseId", "--jq", ".[0].databaseId", allow_failure: true).to_s
        id.empty? ? nil : id
      end

      def watch(run_id) = @shell.run("gh", "run", "watch", run_id, "--repo", repo, "--exit-status", as_me: true, allow_failure: true)

      private

      def variable_of(destination, name)
        value = variables(env: destination)[name].to_s
        value = variables[name].to_s if value.empty?
        value.empty? ? nil : value
      end

      def env_flag(env) = env ? [ "--env", env ] : []
    end
  end
end
