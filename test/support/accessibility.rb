# frozen_string_literal: true

# axe (test/vendor/axe.min.js, axe-core 4.14.0, MPL-2.0) run on what a
# system test is looking at, held to WCAG 2.2 A and AA: a name for every
# field and everything that can be pressed, roles, contrast, and targets
# big enough or far enough apart to press. A violation
# fails the test with each rule, its impact and the elements it found.
module Accessibility
  AXE = Rails.root.join("test/vendor/axe.min.js")
  RULES = %w[wcag2a wcag2aa wcag21a wcag21aa wcag22aa].freeze
  # How long axe may take: Capybara gives an async script its wait time,
  # and a whole page on a busy CI machine takes longer.
  WITHIN = 30

  def assert_accessible(where = page.current_path)
    assert_empty axe_violations, "axe on #{where}"
  end

  # What axe finds in the element `within` names, the whole page by default,
  # once what is moving has come to rest: halfway through a fade (a submit
  # button turning on as the last field is filled) a colour is one the
  # reader never settles on, and axe would judge it. A loop that never ends
  # (a "replying" dot) is left running.
  def axe_violations(within: "html")
    page.execute_script(AXE.read) unless page.evaluate_script("typeof window.axe === 'object'")
    using_wait_time(WITHIN) do
      page.evaluate_async_script(<<~JS, within, RULES)
        const [selector, rules, done] = arguments;
        const settling = document.getAnimations()
          .filter(animation => animation.effect?.getComputedTiming().iterations !== Infinity)
          .map(animation => animation.finished.catch(() => null));
        Promise.all(settling)
           .then(() => axe.run(document.querySelector(selector), { runOnly: { type: "tag", values: rules } }))
           .then(result => done(result.violations.map(v => `${v.id} (${v.impact}): ${v.help} — ${v.nodes.slice(0, 3).map(n => n.target.join(" ")).join(", ")}`)))
           .catch(error => done([`axe failed: ${error}`]));
      JS
    end
  end
end
