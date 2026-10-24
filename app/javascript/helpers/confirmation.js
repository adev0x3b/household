// What the confirm dialog's button says for one press, and whether it is
// set apart as destructive. Turbo hands over the form it is about to submit
// and the button submitting it. A link with data-turbo-method has no button:
// Turbo submits a form of its own made from the link, keeping only the
// question, so the link the reader pressed is passed in as `press` and
// names the button when it asked the same question.
export function confirmationFor(question, { form, submitter = null, press = null }) {
  const asker = submitter ?? (press?.getAttribute("data-turbo-confirm") === question ? press : null)

  return { confirm: nameOf(asker), danger: deletes(form) }
}

// An icon button is named by its aria-label, a menu entry by its words.
function nameOf(element) {
  if (!element) return undefined

  return element.getAttribute("aria-label")?.trim() || element.textContent.trim() || undefined
}

// Rails' button_to carries a method other than POST in a hidden _method
// field; Turbo's form made from a link carries it as the form's method.
function deletes(form) {
  const method = form.querySelector("input[name='_method']")?.value ?? form.getAttribute("method") ?? ""

  return method.toLowerCase() === "delete"
}
