# frozen_string_literal: true

require "test_helper"

# What runs here, one row per destination, from Kamal's labels on the
# containers and the app's health check.
class Provision::StatusTest < ActiveSupport::TestCase
  include ProvisionFakes

  FakeDocker = Struct.new(:list) do
    def containers(**) = list
  end

  def container(name, labels, status: "Up 3 days (healthy)", image: "ghcr.io/owner/household:abc1234def")
    { "Names" => name, "Image" => image, "Status" => status, "State" => status.start_with?("Up") ? "running" : "exited",
      "labels" => labels }
  end

  test "a pipeline's destinations: Kamal's labels, the version from the container's name, the health through the proxy" do
    containers = [
      container("household-web-demo-82e1df8abc", { "service" => "household", "destination" => "demo", "role" => "web" }),
      container("household-job-demo-82e1df8abc", { "service" => "household", "destination" => "demo", "role" => "job" }),
      container("household-demo-db", { "service" => "household-demo-db" }),
      container("household-web-dev-1234567abc", { "service" => "household", "destination" => "dev", "role" => "web" }, status: "Exited (0) 2 days ago"),
      container("household-dev-db", { "service" => "household-dev-db" }, status: "Exited (0) 2 days ago"),
      container("household-db", { "service" => "household-db" })
    ]
    with_installation do |installation|
      shell = Shell.new(answers: { /curl .*Host: demo.example.com.*8080\/up/ => "200" })
      rows = Provision::Status.new(installation: installation, docker: FakeDocker.new(containers), shell: shell).rows(%w[production demo dev])
      production, demo, dev = rows
      assert_equal [ "example.com", nil, nil, "Up 3 days (healthy)", nil ], [ production.host, production.web, production.job, production.db, production.health ]
      assert_equal [ "demo.example.com", "82e1df8", "Up 3 days (healthy)", "Up 3 days (healthy)", "Up 3 days (healthy)", "200" ],
                   [ demo.host, demo.version, demo.web, demo.job, demo.db, demo.health ]
      assert demo.configured
      assert_equal [ "1234567", "Exited (0) 2 days ago", nil ], [ dev.version, dev.web, dev.health ]
      table = Provision::Status.new(installation: installation, docker: FakeDocker.new(containers), shell: shell).table(rows)
      assert_match(/demo\s+demo\.example\.com\s+✓\s+web 82e1df8 · job · db\s+200/, table)
      assert_match(/dev\s+dev\.example\.com\s+–\s+web 1234567 · db \(stopped\)/, table)
    end
  end

  test "a destination on a machine of its own is asked over SSH, and the row names the machine" do
    [ container("household-web-demo-82e1df8abc", { "service" => "household", "destination" => "demo", "role" => "web" }) ]
    with_installation do |installation|
      installation.write_destination("demo", "DEPLOY_HOST" => "other.example")
      shell = Shell.new(answers: { /\Assh -o BatchMode=yes deploy@other.example docker ps/ => "household-web-demo-82e1df8abc\tghcr.io/o/h:82e1df8abc\tUp 1 hour (healthy)\trunning\thousehold\tdemo\tweb",
                                   /\Assh -o BatchMode=yes deploy@other.example curl .*Host:\\ demo.example.com/ => "200" })
      row = Provision::Status.new(installation: installation, docker: Provision::Docker.new(shell), shell: shell).rows(%w[demo production]).first
      assert_equal [ "demo.example.com @ other.example", "82e1df8", "200" ], [ row.host, row.version, row.health ]
      assert shell.ran?(/\Adocker ps -a/), "this machine's containers for production"
      assert_equal 1, shell.commands.count { _1.include?("deploy@other.example docker ps") }, "the other machine asked once"
    end
  end

  private

  def with_installation
    Dir.mktmpdir do |dir|
      root = File.join(dir, "checkout")
      FileUtils.mkdir_p(File.join(root, ".kamal"))
      File.write(File.join(root, ".kamal", "env"), "DEPLOY_HOST=box\nPRODUCTION_HOST=example.com\nSTAGING_HOST=staging.example.com\nDEV_HOST=dev.example.com\nDEMO_HOST=demo.example.com\n")
      installation = Provision::Installation.new(config_dir: File.join(dir, "config"), root: root)
      installation.write_destination("demo", "UPLOADS" => "off")
      yield installation
    end
  end
end
