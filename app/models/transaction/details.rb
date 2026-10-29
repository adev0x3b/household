# frozen_string_literal: true

class Transaction
  # The money: how much, which way, what for, how it was paid, with whom —
  # and what it is about (Costable): the series' row names a series or a
  # purchase, a day's row names that day. The counterparty is a series fact.
  class Details < ::Details::Base
    self.table_name = "transaction_details"

    PURCHASE_TYPES = %w[SupplyPurchase IngredientPurchase].freeze

    attr_writer :counterparty_mode

    belongs_to :counterparty_profile, class_name: "Profile", optional: true
    belongs_to :about, polymorphic: true, optional: true

    enum :kind, { income: 0, expense: 1 }
    enum :category, {
      salary: 0, freelance: 1, bonus: 2, refund: 3, housing: 4, utilities: 5, groceries: 6, transportation: 7,
      healthcare: 8, education: 9, entertainment: 10, shopping: 11, insurance: 12, taxes: 13, savings: 14,
      debt: 15, miscellaneous: 16, dining_out: 17
    }
    enum :payment_method, { card: 0, cash: 1, bank_transfer: 2 }

    # A transfer to savings moves money the household keeps, so it is
    # neither spent nor out of its cash flow: the money figures read every
    # category but it, and the savings rate reads it alone.
    def self.cash_categories = categories.keys - %w[savings]

    inherits :kind, :category, :amount_cents, :currency, :payment_method, :counterparty

    # A payment made stays as it was made: a later change to the series
    # (the rent going up) is for the payments still to come.
    def self.recorded = %i[kind category amount_cents currency payment_method counterparty]
    series_requires :kind, :category, :amount_cents, :currency, :payment_method

    before_validation :normalize_counterparty_selection
    before_validation :normalize_currency
    before_save :keep_out_of_mail, if: :about_changed?

    validates :currency, format: { with: /\A[A-Z]{3}\z/ }, allow_nil: true
    validate :amount_must_be_positive
    validate :amount_must_fit_currency
    validate :counterparty_selection_must_be_exclusive
    validate :counterparty_profile_cannot_match_owner
    validate :counterparty_only_on_series
    validate :about_must_take_costs
    validates_accessible :about, by: -> { event&.profile }
    validates_within_household :counterparty_profile, of: -> { event&.profile }

    def self.opposite_kind(kind) = kind.to_s == "income" ? "expense" : "income"

    def counterparty_mode
      @counterparty_mode.presence || (counterparty_profile_id.present? ? "profile" : "text")
    end

    def amount
      cents = amount_cents
      return if cents.nil?

      BigDecimal(cents.to_s) / CURRENCY_SCALE
    end

    def amount=(value)
      self.amount_cents = Transaction.amount_to_cents(value)
    end

    def counterparty_display_name
      return counterparty if counterparty.present?
      return unless counterparty_profile

      counterparty_profile.display_name
    end

    private

    # Once about something a mail doesn't name, a payment is never named in
    # mail again, even after that thing is deleted or another is chosen: its
    # title may still be the one made after it, by the app or by whoever
    # added the cost (Transaction#reminder_mail_thing).
    def keep_out_of_mail
      self.named_in_mail = false if about && !about.named_in_mail?
    end

    # A day's currency as it will be stored, upper case, before #assign_own
    # compares it with the series'.
    def normalize_for_comparison = normalize_currency

    def normalize_currency
      self.currency = self[:currency].to_s.strip.upcase.presence
    end

    def normalize_counterparty_selection
      self.counterparty = self[:counterparty].to_s.strip.presence

      case @counterparty_mode
      when "profile" then self.counterparty = nil
      when "text" then self.counterparty_profile = nil
      end
    end

    # The kind says which way the money went, so the amount is how much
    # alone: a typed sign would say the direction a second time, and could
    # say it differently.
    def amount_must_be_positive
      cents = self[:amount_cents]
      return if cents.nil? || cents.positive?

      errors.add(:amount, :must_be_positive)
    end

    # Every amount is kept in hundredths, so a stored 120050 for yen would
    # show as ¥1,201: an amount finer than its currency's smallest unit is
    # refused rather than rounded behind the person's back.
    def amount_must_fit_currency
      cents = self[:amount_cents]
      return if cents.nil? || currency.blank?

      smallest = CURRENCY_SCALE / (10**Currency.new(currency).decimals)
      errors.add(:amount, :too_fine, currency: currency) unless (cents % smallest).zero?
    end

    def counterparty_selection_must_be_exclusive
      return if self[:counterparty].blank? || counterparty_profile_id.blank?

      errors.add(:counterparty, :name_and_member)
    end

    def counterparty_profile_cannot_match_owner
      return if counterparty_profile_id.blank? || event&.profile_id.blank?

      errors.add(:counterparty_profile, :yourself) if counterparty_profile_id == event.profile_id
    end

    def counterparty_only_on_series
      return if series? || counterparty_profile_id.blank?

      errors.add(:counterparty_profile, :series_only)
    end

    # A series' row is about a series or a purchase, a day's row about a
    # day, and only about things that take costs.
    def about_must_take_costs
      return if about.nil?
      return errors.add(:about, :invalid) unless series? ? about_series_or_purchase? : about.is_a?(Occurrence)

      errors.add(:about, :takes_no_costs) unless about.costable?
    end

    def about_series_or_purchase? = about.is_a?(Event) || PURCHASE_TYPES.include?(about.class.name)
  end
end
