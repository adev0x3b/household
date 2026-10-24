# frozen_string_literal: true

# Whether code waits for a lock that someone else holds. A connection of its
# own takes the lock and keeps it while the code runs on a thread of its
# own; the assertion passes once Postgres says that thread is blocked by the
# holder, and fails if the code finishes first. Then the lock is let go, the
# code finishes, and whatever it raised is raised here.
#
# A record's row is held FOR KEY SHARE, the weakest lock that stands in the
# way of the code's own SELECT … FOR UPDATE: its plain updates of the row,
# and the rows it adds that point at it, go through, so only locking the row
# is made to wait. Code that locks the row FOR NO KEY UPDATE is held up only
# from FOR SHARE, which its plain updates wait for too, so its test picks a
# case that doesn't update the row.
#
#   assert_waits_for_lock(household) { Households::Invite.call(household, …) }     # the record's row
#   assert_waits_for_lock(event, holding: "FOR SHARE") { event.advance_unsaved_from! }
#   assert_waits_for_lock(advisory: KEY) { Admins::Create.call(…) }             # an advisory lock
#
# A race run on two threads, counting who won, passes most of the time with
# the lock gone; this fails every time. Each thread needs a connection of its
# own, which a transactional test doesn't give: a test that uses it turns
# them off (LocksTest).
module RowLocks
  def assert_waits_for_lock(record = nil, holding: "FOR KEY SHARE", advisory: nil, &code)
    pool = ActiveRecord::Base.connection_pool
    holder = pool.checkout
    holder.begin_db_transaction
    holder.execute(record ? hold_row(record, holding) : "SELECT pg_advisory_xact_lock(#{Integer(advisory)})")
    worker, waiter = run_aside(pool, &code)

    blocked = false
    assert_eventually("the code neither waited for the lock nor finished", within: 5) do
      (blocked = blocked_by?(holder, waiter)) || !worker.alive?
    end
    assert blocked, "the code finished without waiting for the lock"
  ensure
    if holder
      holder.rollback_db_transaction
      pool.checkin(holder)
    end
    worker&.value
  end

  private

  def hold_row(record, mode) = "SELECT 1 FROM #{record.class.quoted_table_name} WHERE id = #{Integer(record.id)} #{mode}"

  # The thread running `code`, and its connection's backend.
  def run_aside(pool, &code)
    started = Queue.new
    worker = Thread.new do
      pool.with_connection do |connection|
        started << connection.select_value("SELECT pg_backend_pid()")
        code.call
      end
    end
    worker.report_on_exception = false
    [ worker, started.pop(timeout: 5) ]
  end

  # Asked again each time: the query cache would answer with the first reply.
  def blocked_by?(holder, backend)
    holder.uncached { holder.select_value("SELECT pg_backend_pid() = ANY(pg_blocking_pids(#{Integer(backend)}))") }
  end
end
