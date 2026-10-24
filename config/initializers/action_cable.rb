# frozen_string_literal: true

# Solid Cable writes broadcasts from a thread of its own, a few at a time. A
# process that broadcasts and then ends (the eval run telling whoever started
# it how it went) would take what is still queued with it, so the adapter is
# shut down at exit, which writes the queue out first.
at_exit { ActionCable.server.pubsub.shutdown }
