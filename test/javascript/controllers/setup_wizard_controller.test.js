import { test, afterEach } from "node:test"
import assert from "node:assert/strict"
import { mount } from "../support/stimulus.js"
import SetupWizardController from "../../../app/javascript/controllers/setup_wizard_controller.js"

// The first setup as Views::Setup::Show draws it, cut down to a field or
// two a step: who you are, what the installation allows, the assistant
// (asked only while its switch is on), who else lives here, and the review.
function page({ start = 0 } = {}) {
  return `
    <form data-controller="setup-wizard" data-action="keydown.enter->setup-wizard#enter"
          data-setup-wizard-start-value="${start}" data-setup-wizard-progress-value="Step %{current} of %{total}: %{title}"
          data-setup-wizard-on-value="On" data-setup-wizard-off-value="Off" data-setup-wizard-set-value="Typed"
          data-setup-wizard-unset-value="Not set" data-setup-wizard-change-value="Change">
      <p data-setup-wizard-target="progress" hidden></p>
      <div data-setup-wizard-target="step">
        <section class="panel"><h2 class="panel__title">You</h2>
          <label class="label" for="username">Username<span>*</span></label>
          <input id="username" name="setup[account][username]" required>
          <label class="label" for="password">Password</label>
          <input id="password" type="password" name="setup[account][password]" required>
        </section>
      </div>
      <div data-setup-wizard-target="step">
        <section class="panel"><h2 class="panel__title">What this installation allows</h2>
          <label><input type="hidden" name="setup[allowances][assistant]" value="0">
            <input id="assistant" type="checkbox" name="setup[allowances][assistant]" value="1" checked>
            <span><strong>The assistant</strong><span class="help">A chat.</span></span></label>
          <label class="label" for="budget">Assistant messages per day</label>
          <input id="budget" type="number" name="setup[allowances][assistant_messages_per_day]" placeholder="No limit">
        </section>
      </div>
      <div data-setup-wizard-target="step">
        <div data-setup-wizard-when="setup[allowances][assistant]">
          <section class="panel"><h2 class="panel__title">Model</h2>
            <label class="label" for="model">Model</label>
            <input id="model" name="setup[assistant][model]" required>
          </section>
        </div>
      </div>
      <div data-setup-wizard-target="step">
        <section class="panel"><h2 class="panel__title">Who else lives here</h2></section>
      </div>
      <div data-setup-wizard-target="step review" hidden>
        <section class="panel"><h2 class="panel__title">Check and create</h2>
          <div data-setup-wizard-target="summary"></div>
        </section>
      </div>
      <button type="button" class="back" data-setup-wizard-target="back" data-action="setup-wizard#back">Back</button>
      <button type="button" class="next" data-setup-wizard-target="next" data-action="setup-wizard#next">Next</button>
      <button type="submit" class="create" data-setup-wizard-target="create" data-action="setup-wizard#create">Create</button>
    </form>
  `
}

let mounted
afterEach(() => mounted.stop())

const $ = (selector) => document.querySelector(selector)
const shownSteps = () =>
  [...document.querySelectorAll('[data-setup-wizard-target~="step"]')].filter((step) => !step.hidden)
const shownTitle = () => shownSteps()[0].querySelector(".panel__title").textContent
const fill = (selector, value) => ($(selector).value = value)

test("shows the first step alone, says where the person is, and offers Next only", async () => {
  mounted = await mount("setup-wizard", SetupWizardController, page())

  assert.equal(shownSteps().length, 1)
  assert.equal(shownTitle(), "You")
  assert.equal($('[data-setup-wizard-target="progress"]').textContent, "Step 1 of 5: You")
  assert.equal($(".back").hidden, true)
  assert.equal($(".next").hidden, false)
  assert.equal($(".create").hidden, true)
})

test("Next stays on a step whose fields aren't filled in, and moves on once they are", async () => {
  mounted = await mount("setup-wizard", SetupWizardController, page())

  $(".next").click()
  assert.equal(shownTitle(), "You")

  fill("#username", "alex")
  fill("#password", "a-long-password")
  $(".next").click()
  assert.equal(shownTitle(), "What this installation allows")
  assert.equal($(".back").hidden, false)

  $(".back").click()
  assert.equal(shownTitle(), "You")
  assert.equal($("#username").value, "alex", "going back keeps what was typed")
})

test("with the assistant off its step is skipped, and the count says so", async () => {
  mounted = await mount("setup-wizard", SetupWizardController, page({ start: 1 }))

  $("#assistant").checked = false
  $(".next").click()
  assert.equal(shownTitle(), "Who else lives here")
  assert.equal($('[data-setup-wizard-target="progress"]').textContent, "Step 3 of 4: Who else lives here")
})

test("Enter in a field moves on rather than sending the form", async () => {
  mounted = await mount("setup-wizard", SetupWizardController, page())
  fill("#username", "alex")
  fill("#password", "a-long-password")

  const enter = new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })
  $("#username").dispatchEvent(enter)
  assert.equal(enter.defaultPrevented, true)
  assert.equal(shownTitle(), "What this installation allows")
})

test("the review lists every answer by its card, a typed secret as typed, and Change goes back to its step", async () => {
  mounted = await mount("setup-wizard", SetupWizardController, page({ start: 3 }))
  fill("#username", "alex")
  fill("#password", "a-long-password")
  fill("#model", "qwen3:8b")

  $(".next").click()
  assert.equal(shownTitle(), "Check and create")
  assert.equal($(".next").hidden, true)
  assert.equal($(".create").hidden, false)

  const groups = [...document.querySelectorAll(".setup__summary-group")]
  const answers = groups.map((group) => [
    group.querySelector("h3").textContent,
    [...group.querySelectorAll("dt")].map((term) => `${term.textContent}: ${term.nextElementSibling.textContent}`)
  ])
  assert.deepEqual(answers, [
    ["You", ["Username: alex", "Password: Typed"]],
    ["What this installation allows", ["The assistant: On", "Assistant messages per day: No limit"]],
    ["Model", ["Model: qwen3:8b"]]
  ])

  groups[1].querySelector("button").click()
  assert.equal(shownTitle(), "What this installation allows")
})

test("Create opens the first step still wrong instead of sending, and a skipped step sends nothing", async () => {
  mounted = await mount("setup-wizard", SetupWizardController, page({ start: 4 }))
  $("#assistant").checked = false

  const click = new MouseEvent("click", { bubbles: true, cancelable: true })
  $(".create").dispatchEvent(click)
  assert.equal(click.defaultPrevented, true)
  assert.equal(shownTitle(), "You")
  assert.equal($("#model").disabled, true)

  $("#assistant").checked = true
  fill("#username", "alex")
  fill("#password", "a-long-password")
  fill("#model", "qwen3:8b")
  $(".create").dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))
  assert.equal($("#model").disabled, false, "a step asked again sends its fields again")
})
