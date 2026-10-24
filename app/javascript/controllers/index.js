import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"

// Every controller pinned under "controllers" registers itself from its file name.
eagerLoadControllersFrom("controllers", application)
