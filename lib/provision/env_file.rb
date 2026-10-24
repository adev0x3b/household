# frozen_string_literal: true

require "fileutils"

module Provision
  # A destination's file, ~/.config/household/<destination>.env, and
  # .kamal/env: NAME=value lines that Dotenv (bin/kamal), Docker Compose
  # (--env-file) and a shell read alike. A value is written bare when every
  # reader takes it so, in double quotes otherwise; a value with a line
  # break has no safe spelling and is refused.
  module EnvFile
    LINE = /\A\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*\z/
    BARE = %r{\A[A-Za-z0-9_@%+=:,./-]*\z}

    def self.parse(text)
      text.each_line.with_object({}) do |line, pairs|
        next if line.strip.empty? || line.lstrip.start_with?("#")

        match = LINE.match(line.chomp) or next
        pairs[match[1]] = unquote(match[2])
      end
    end

    def self.render(pairs, header: nil)
      lines = header.to_s.lines.map { "# #{_1.chomp}".rstrip + "\n" }
      lines << "\n" if lines.any?
      pairs.each { |name, value| lines << "#{name}=#{quote(value.to_s)}\n" }
      lines.join
    end

    def self.read(path) = File.exist?(path) ? parse(File.read(path)) : {}

    # Written whole, readable by its owner alone.
    def self.write(path, pairs, header: nil)
      FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
      File.write(path, render(pairs, header: header), perm: 0o600)
      File.chmod(0o600, path)
    end

    def self.quote(value)
      raise ArgumentError, "a value can't hold a line break" if value.include?("\n")
      return value if value.match?(BARE)

      # A shell runs a backquoted command even inside double quotes.
      %("#{value.gsub(/[\\"$`]/) { "\\#{_1}" }}")
    end

    def self.unquote(value)
      if value.start_with?('"') && value.end_with?('"') && value.length >= 2
        value[1...-1].gsub(/\\(["\\$`])/, '\1')
      elsif value.start_with?("'") && value.end_with?("'") && value.length >= 2
        value[1...-1]
      else
        value.sub(/\s+#.*\z/, "")
      end
    end
  end
end
