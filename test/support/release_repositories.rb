# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

# A git repository of its own for each test of bin/release, its main
# written the way GitHub writes it: a merge commit for each pull request.
module ReleaseRepositories
  class Builder
    attr_reader :root

    def initialize(root)
      @root = root
      git("init", "--quiet", "--initial-branch=main")
      git("config", "user.name", "Test")
      git("config", "user.email", "test@example.com")
      git("config", "commit.gpgsign", "false")
      git("config", "tag.gpgsign", "false")
    end

    # A commit straight on the branch checked out, its files written first.
    def commit(message, files = { "README.md" => message })
      files.each do |path, content|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), content)
      end
      git("add", "--all")
      git("commit", "--quiet", "--allow-empty", "--message", message)
      head
    end

    def merge_pull_request(number, title, files = { "pr-#{number}.txt" => title })
      git("checkout", "--quiet", "-b", "pr-#{number}")
      commit(title, files)
      git("checkout", "--quiet", "main")
      message = "Merge pull request ##{number} from owner/pr-#{number}\n\n#{title}"
      git("merge", "--quiet", "--no-ff", "pr-#{number}", "--message", message)
      head
    end

    def tag(name, commit = "HEAD") = git("tag", name, commit)
    def head = git("rev-parse", "HEAD").strip

    def git(*args)
      output, status = Open3.capture2e("git", *args, chdir: root)
      raise "git #{args.join(" ")}: #{output}" unless status.success?

      output
    end
  end

  def with_repository
    Dir.mktmpdir("release") { yield Builder.new(_1) }
  end
end
