# frozen_string_literal: true

require "test_helper"

# The documentation can be walked: every link between its pages and to the
# repository's files leads somewhere, an anchor to a heading the page has,
# every page under docs/ is reached from docs/README.md, and each one says
# where it sits with its breadcrumb line under the title.
class DocLinksTest < ActiveSupport::TestCase
  PAGES = %w[*.md .github/**/*.md docs/**/*.md].freeze
  FRONT_DOOR = "docs/README.md"

  LINK = /\]\(([^)\s]+)\)|<(?:img|a)\s[^>]*?(?:src|href)="([^"]+)"/
  BREADCRUMB = /\A\[Documentation\]\([^)]+\)/

  test "every link leads to a file of the repository or a heading of its page" do
    broken = pages.flat_map do |page|
      links_of(page).filter_map { |target, line| "#{page}:#{line}: #{target}" unless leads_somewhere?(page, target) }
    end
    assert_empty broken, "Linked but not there (moved? renamed?)"
  end

  test "every page under docs is reached from the front door" do
    reached = Set[FRONT_DOOR]
    unread = [ FRONT_DOOR ]
    while (page = unread.shift)
      links_of(page).each do |target, _|
        path = path_of(page, target)
        unread << path if path.start_with?("docs/") && path.end_with?(".md") && File.exist?(path) && reached.add?(path)
      end
    end
    assert_empty Dir["docs/**/*.md"] - reached.to_a, "No way there from #{FRONT_DOOR}"
  end

  test "every page under docs but the front door has its breadcrumb under the title" do
    missing = (Dir["docs/**/*.md"] - [ FRONT_DOOR ]).reject { |page| File.readlines(page)[2]&.match?(BREADCRUMB) }
    assert_empty missing, "Without a breadcrumb line"
  end

  private

  def pages = Dir[*PAGES].uniq

  # [target, line number] for every link outside code: a fenced block or a
  # span in backticks shows a link's syntax, it isn't one.
  def links_of(page)
    fenced = false
    File.foreach(page).with_index(1).flat_map do |line, number|
      fenced = !fenced if line.start_with?("```")
      next [] if fenced || line.start_with?("```")

      line.gsub(/`[^`]*`/, "").scan(LINK).map { |markdown, html| [ markdown || html, number ] }
    end
  end

  def leads_somewhere?(page, target)
    return true if target.match?(/\A[a-z]+:/)

    file, anchor = target.split("#", 2)
    path = file.empty? ? page : path_of(page, file)
    return false unless File.exist?(path)

    anchor.nil? || !path.end_with?(".md") || anchors_of(path).include?(anchor)
  end

  def path_of(page, target)
    Pathname(File.dirname(page)).join(target.split("#").first).cleanpath.to_s
  end

  # The anchors GitHub gives a page's headings: lower case, punctuation
  # dropped, spaces made hyphens, and a number after a repeated one.
  def anchors_of(path)
    @anchors ||= {}
    @anchors[path] ||= begin
      seen = Hash.new(0)
      headings_of(path).map do |heading|
        slug = heading.downcase.gsub(/[^\p{Alnum}\- _]/, "").tr(" ", "-")
        count = seen[slug]
        seen[slug] += 1
        count.zero? ? slug : "#{slug}-#{count}"
      end
    end
  end

  def headings_of(path)
    fenced = false
    File.foreach(path).filter_map do |line|
      fenced = !fenced if line.start_with?("```")
      line[/\A#+\s+(.+)/, 1]&.strip unless fenced
    end
  end
end
