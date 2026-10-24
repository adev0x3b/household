# frozen_string_literal: true

require "test_helper"

# What the documentation and the code's comments name still exists: every
# namespaced class or constant and every class's method that docs/, the
# README, CONTRIBUTING, SECURITY or a comment in the code names, and every
# class a page names alone in backticks. A rename that
# leaves a page or a comment behind fails here, with where. A name written
# without its namespace counts when a loaded module ends with it, as the
# docs shorten them.
class DocNamesTest < ActiveSupport::TestCase
  # Names the docs use that aren't the app's, each with why.
  NOT_OURS = {
    "Namespace::Verb" => "a placeholder for any service",
    "WebAssembly" => "the browser's",
    "DataTransfer" => "the browser's",
    "HostKeyAlias" => "an SSH option",
    "HostKeyMismatch" => "an SSH error"
  }.freeze

  PAGES = %w[README.md CONTRIBUTING.md SECURITY.md docs/**/*.md].freeze
  CODE = %w[app/**/*.rb lib/**/*.rb config/**/*.rb test/**/*.rb bin/* db/seeds.rb].freeze

  CONSTANT = /\b[A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)+/
  # A method follows its class after "#" or "."; a name running on into a
  # capital letter is JavaScript's camelCase (toJSON), not ours.
  METHOD = /\b([A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*)[#.]([a-z_][a-z0-9_]*[?!=]?)(?![A-Za-z0-9])/
  ALONE = /`([A-Z][a-z][A-Za-z0-9]*)`/
  FILE_ENDINGS = %w[rb js md yml yaml scss css erb html json png jpg svg txt com site io org env dev new].freeze

  setup { Rails.application.eager_load! }

  test "every class and constant the docs and comments name exists" do
    missing = mentions.filter_map { |kind, name, where| "#{where}: #{name}" if kind != :method && !constant?(name) }
    assert_empty missing.uniq, "Named but not in the app (renamed? removed?)"
  end

  test "every method the docs and comments name exists" do
    missing = mentions.filter_map { |kind, (owner, name), where| "#{where}: #{owner}##{name}" if kind == :method && !method?(owner, name) }
    assert_empty missing.uniq, "Named but not in the app (renamed? removed?)"
  end

  private

  # The pages read whole, and the files whose comments are read.
  def pages = Dir[*PAGES]
  def commented_files = Dir[*CODE].select { File.file?(_1) }

  def not_ours?(name) = NOT_OURS.key?(name)

  # [kind, name, "file:line"] for every name a page or a comment gives.
  def mentions
    pages = self.pages.flat_map { |path| lines_of(path) { true } }
    comments = commented_files.flat_map { |path| lines_of(path) { |line| line.lstrip.start_with?("#") } }

    (pages + comments).flat_map do |line, where, page|
      found = line.scan(CONSTANT).map { [ :constant, _1, where ] }
      found += line.scan(ALONE).flatten.map { [ :alone, _1, where ] } if page
      found + line.scan(METHOD).filter_map { |owner, name| [ :method, [ owner, name ], where ] unless FILE_ENDINGS.include?(name) }
    end
  end

  def lines_of(path)
    page = path.end_with?(".md")
    File.foreach(path).with_index(1).filter_map { |line, number| [ line, "#{path}:#{number}", page ] if yield(line) }
  end

  def constant?(name)
    return true if not_ours?(name) || name.safe_constantize || ending_with(name).any?
    return true if test_class?(name)

    owner, _, last = name.rpartition("::")
    ending_with(owner).any? { |mod| mod.const_defined?(last, false) }
  end

  def method?(owner, name)
    return true if not_ours?(owner)

    ending_with(owner).any? do |mod|
      [ name, "#{name.delete_suffix("=")}=" ].any? { |it| defines?(mod, it) } ||
        (mod.respond_to?(:column_names) && mod.table_exists? && mod.column_names.include?(name.delete("?=")))
    end
  end

  def defines?(mod, name)
    mod.method_defined?(name) || mod.private_method_defined?(name) || mod.respond_to?(name, true) ||
      (mod.const_defined?(:ClassMethods, false) && mod::ClassMethods.method_defined?(name)) ||
      (mod.respond_to?(:reflect_on_association) && mod.reflect_on_association(name)) ||
      (mod.respond_to?(:defined_enums) && mod.defined_enums.any? { |enum, values| enum == name || values.key?(name.delete("?!")) })
  end

  # A test's class is loaded only where its file runs, so it is looked for
  # in the files instead: the name up to its first segment ending in Test
  # or TestCase, declared whole (Households::DestroyTest), inside its
  # module, or with a namespace the name leaves out.
  def test_class?(name)
    segments = name.split("::")
    index = segments.index { |segment| segment.end_with?("Test", "TestCase") }
    return false if index.nil?

    [ segments[..index].join("::"), segments[index] ].any? do |declared|
      test_sources.match?(/^\s*(class|module)\s+(\w+::)*#{Regexp.escape(declared)}\b/)
    end
  end

  def test_sources = @test_sources ||= Dir["test/**/*.rb"].map { File.read(_1) }.join("\n")

  def ending_with(name)
    modules.filter_map { |full, mod| mod if full == name || full.end_with?("::#{name}") }
  end

  # Every named module with its name, read through Module#name itself,
  # since a class may define a `name` of its own.
  def modules
    @modules ||= ObjectSpace.each_object(Module).filter_map do |mod|
      full = Module.instance_method(:name).bind_call(mod)
      [ full, mod ] if full
    end
  end
end
