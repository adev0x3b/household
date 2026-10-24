# frozen_string_literal: true

# Money is only ever changed by its owner (or a linked housemate the owner
# lets): a share shows it, and the counterparty of a payment between
# housemates reads it from their side without touching it.
class TransactionOccurrencePolicy < OccurrencePolicy
  def show?
    super || counterparty?
  end

  private

  def shared_writable? = false

  def writable?
    return false if counterparty? && !owner?

    super
  end

  def deletable?
    return false if counterparty? && !owner?

    super
  end

  def counterparty?
    record.event.counterparty?(user)
  end
end
