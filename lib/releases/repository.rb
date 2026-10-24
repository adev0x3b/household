# frozen_string_literal: true

require "open3"

module Releases
  # The checkout a release is prepared from: its release tags, its history
  # and a commit's files. The history must be whole, since a release looks
  # back to the one before it.
  class Repository
    # A merge GitHub made for a pull request: its subject names the number,
    # and its message's first line after that is the pull request's title.
    PULL_REQUEST_MERGE = /\AMerge pull request #(\d+) /

    Change = Data.define(:title, :reference)

    def initialize(root)
      @root = root
    end

    # The full sha of a commit, however it is named.
    def commit(name)
      git("rev-parse", "--verify", "--quiet", "#{name}^{commit}").strip
    rescue Error
      raise Error, "There's no commit #{name} in this checkout."
    end

    # Every release so far: { Version => the commit its tag names }.
    def releases
      git("for-each-ref", "refs/tags/v*", "--format=%(refname:short) %(objectname) %(*objectname)").lines.to_h do |line|
        tag, object, tagged_commit = line.split
        [ Version.parse(tag), tagged_commit || object ]
      end.except(nil)
    end

    def ancestor?(older, newer)
      _output, status = Open3.capture2e("git", "merge-base", "--is-ancestor", older, newer, chdir: @root)
      status.success?
    end

    # A file as a commit has it, or nil where the commit has none.
    def file(commit, path)
      output, status = Open3.capture2("git", "show", "#{commit}:#{path}", chdir: @root, err: File::NULL)
      output if status.success?
    end

    # The files added between two commits under a directory.
    def added(from, to, under:)
      git("diff", "--name-only", "--diff-filter=A", from, to, "--", under).lines(chomp: true)
    end

    # What main gained between two commits, oldest first: a merged pull
    # request by its title and number, any other commit by its subject and
    # short sha.
    def changes(from, to)
      log = git("log", "--first-parent", "--reverse", "--format=%h%x00%s%x00%b%x1e", "#{from}..#{to}")
      log.split("\x1e").map(&:strip).reject(&:empty?).map do |entry|
        short, subject, body = entry.split("\x00", 3)
        if (number = subject[PULL_REQUEST_MERGE, 1]) && !(title = body.to_s.lines.first.to_s.strip).empty?
          Change.new(title, "##{number}")
        else
          Change.new(subject, short)
        end
      end
    end

    private

    def git(*args)
      output, error, status = Open3.capture3("git", *args, chdir: @root)
      raise Error, "git #{args.first} failed: #{error.strip}" unless status.success?

      output
    end
  end
end
