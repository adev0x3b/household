# frozen_string_literal: true

module Reports
  # What's planned for the next 7 days (today has its own card), by day:
  # every day of every series still to do, of any kind. Done, skipped and
  # cancelled days are left out. The list is shown PER_PAGE items at a time
  # (#page, a will_paginate collection; a day can run on to the next page),
  # so the card stays a summary and nothing is left out.
  #
  # An item is an Occurrence (saved, or projected and unsaved) with what the
  # list shows of it: its kind (`type`, an Event subclass; its section
  # comes from the series, Event#section), its label, and its time: a
  # dose's slot (`time`, "HH:MM", with the `anchor` it came from) or an
  # appointment's start time.
  class Upcoming
    PER_PAGE = 12

    Item = Data.define(:occurrence, :type, :label, :date, :time, :anchor) do
      def event = occurrence.event
    end
    Day = Data.define(:date, :items)

    # `page` past the last one (days were done since the link was made)
    # shows the last.
    def initialize(audience:, today: Date.current, page: 1, window: Window.new(audience))
      @period = Period.ahead(today: today)
      @today = today
      @page_number = page.to_i
      @window = window
    end

    def any? = open_items.any?

    # The page's items, a WillPaginate::Collection (for Components::Pagination).
    def page
      @page ||= begin
        last = [ (open_items.size / PER_PAGE.to_f).ceil, 1 ].max
        WillPaginate::Collection.create(@page_number.clamp(1, last), PER_PAGE, open_items.size) do |pager|
          pager.replace(open_items[pager.offset, pager.per_page])
        end
      end
    end

    def days
      page.group_by(&:date).map { |date, items| Day.new(date: date, items: items) }
    end

    private

    def open_items
      @open_items ||= @window.ledger(@period, today: @today).entries
        .select { |entry| entry.occurrence.open? }
        .sort_by { |entry| sort_key(entry) }
        .map { |entry| item(entry) }
    end

    def item(entry)
      occurrence = entry.occurrence
      Item.new(
        occurrence: occurrence, type: occurrence.event.class, label: entry.label,
        date: entry.date, time: entry.time, anchor: entry.anchor,
      )
    end

    # In date order, most important first within a day, then by the clock,
    # then by series and slot, which make the order total: the list is
    # paged, and a tie sorted differently on two requests would move an
    # item from one page to the next (sort_by isn't stable).
    def sort_key(entry)
      occurrence = entry.occurrence
      [
        entry.date, -occurrence.priority_rank, *clock_order(occurrence),
        occurrence.event_id, entry.time.to_s, entry.anchor.to_s
      ]
    end

    # A day's slot, else its start time, as "HH:MM"; the untimed days come
    # after the timed ones.
    def clock_order(occurrence)
      clock = occurrence.time_string || occurrence.start_time&.strftime("%H:%M")
      clock ? [ 0, clock ] : [ 1, "" ]
    end
  end
end
