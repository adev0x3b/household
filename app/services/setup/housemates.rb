# frozen_string_literal: true

module Setup
  # The first setup's last question: who else lives here. Each is invited
  # when the household is made (Households::Invite), and their links are
  # shown once at the end, to hand over. Nobody is the answer that needs
  # nothing.
  class Housemates
    include ActiveModel::Model

    attr_reader :people
    # The account's email, which can't be invited too.
    attr_accessor :owner_email
    # The installation's limits as the same form sets them
    # (Installation::Allowances), saved together with these invitations.
    attr_accessor :allowances

    validate :people_are_valid

    def self.param_key = :housemates

    def self.fields = [ people: [ %i[first_name email] ] ]

    def self.for_setup = new

    def initialize(people: [])
      @people = people
    end

    # Rows come keyed by their place on the page, in its order.
    def assign(values)
      rows = values.to_h.symbolize_keys.fetch(:people, {}).to_h
      @people = rows.sort_by { |index, _| index.to_s.to_i }.map { |_, row| Housemate.from(row) }.reject(&:blank?)
      self
    end

    def asked?(_form) = true

    # How many the account may invite: the invitations each member may
    # send, and the household's places but the account's own; nil: no limit.
    def limit
      size = allowances&.household_size
      [ allowances&.invitations_per_member, (size - 1 if size) ].compact.min
    end

    private

    # Each row is checked on its own, and then against the others; the
    # summary names the row, as a form's list does.
    def people_are_valid
      errors.add(:people, :too_many, count: limit) if limit && people.size > limit
      seen = Set.new
      people.each.with_index(1) do |person, number|
        person.valid?
        person.errors.add(:email, :owner) if person.email.present? && person.email == owner_email&.downcase
        person.errors.add(:email, :repeated) if person.email.present? && !seen.add?(person.email)
        person.errors.full_messages.each { |message| errors.add(:base, row(number, message)) }
      end
    end

    def row(number, message)
      return I18n.t("form.errors.alone", list: self.class.human_attribute_name(:people), message:) if people.one?

      I18n.t("form.errors.row", list: self.class.human_attribute_name(:people), number:, message:)
    end
  end
end
