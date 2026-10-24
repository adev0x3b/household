# frozen_string_literal: true

# Reading a response as a person sees it: by its markup, not its bytes. The
# text of a toast is escaped like any other ("isn't" is written "isn&#39;t"),
# and a name may legitimately sit inside an attribute, where it is inert —
# so neither is checked with a substring of the HTML.
module ResponseAssertions
  # A toast says `expected` (a substring, or a Regexp), in its message or its
  # second line. Turbo Stream templates included.
  def assert_toast(expected, html = response.body)
    toasts = shown_toasts(html).map { _1.css(".toast__message, .toast__detail").map(&:text).join(" ").squish }
    matched = toasts.any? { |text| expected.is_a?(Regexp) ? text.match?(expected) : text.include?(expected) }
    assert matched, "no toast says #{expected.inspect}; the toasts were #{toasts.inspect}"
  end

  # The form that didn't save says `expected` (a substring, or a Regexp)
  # among what went wrong, above its fields.
  def assert_form_error(expected, html = response.body)
    errors = parsed(html).css(".notice--critical li").map { _1.text.squish }
    matched = errors.any? { |text| expected.is_a?(Regexp) ? text.match?(expected) : text.include?(expected) }
    assert matched, "the form says nothing like #{expected.inspect}; it said #{errors.inspect}"
  end

  # The toasts a page or a stream shows. The layout also holds a toast for
  # each way a request can fail, in templates only the browser brings out,
  # so those are left out.
  def shown_toasts(html = response.body)
    parsed(html).css(".toast").reject { |toast| toast.ancestors("##{Components::Toast::CONTAINER_ID} > template").any? }
  end

  # No element the payload would have made exists anywhere in the response.
  def assert_no_injected_markup(html = response.body, tag: "img")
    assert_empty parsed(html).css(tag), "a <#{tag}> was injected into the markup"
  end

  private

  # A page, or a Turbo Stream response: Nokogiri reads a <template>'s
  # content as its children, so a stream's markup is searched like a page's.
  def parsed(html) = Nokogiri::HTML5.fragment(html)
end
