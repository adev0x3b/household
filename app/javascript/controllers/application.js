import { Application } from "@hotwired/stimulus"

const application = Application.start()

// On the window for the browser's console: Stimulus.controllers shows what is connected.
window.Stimulus = application

export { application }
