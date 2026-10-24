# frozen_string_literal: true

module Assistant
  module Operations
    # Shares a record with another household member through Shares::Create,
    # as the share modal does, so the person hears about it the same way.
    # It waits for the Apply button, since it shows the user's data to
    # someone else.
    class Share < Base
      def phase = :finishing
      def risky? = true

      def checked_records = [ @record ].compact

      def check
        @record = resolve!
        return if @record.nil?

        @target = @record.is_a?(Occurrence) ? @record.event : @record
        fail!("#{@target.class.name.titleize.downcase.pluralize} can't be shared") unless @target.is_a?(Shareable)

        resolution = Members.new(profile).resolve(fields["with"])
        @candidates = resolution.candidates
        return if @candidates.any?

        fail!(resolution.problem) if resolution.problem
        @member = resolution.profile
        Pundit.authorize(profile, @target, :share?, policy_class: SharePolicy)
        check_sharing(shares.exists?(profile_id: @member.id))
      end

      def apply!(applier)
        entries = write!
        applier.saved([ summarize(@record) ])
        entries
      end

      def label
        return super unless @record

        text = @record.try(:event_label) || @record.try(:name) || super
        date = (@record.date if @record.is_a?(Occurrence))
        date && !@target.try(:recurring?) ? I18n.t("assistant.operations.on_date", thing: text, date: I18n.l(date, format: :long)) : text
      end

      def summary = I18n.t("assistant.operations.#{op}", thing: label, person: @member ? person : fields["with"].to_s)

      private

      # Sharing again is nothing to refuse, only worth a word.
      def check_sharing(shared)
        @notes << "already shared with #{person}" if shared
      end

      def write!
        return [] if shares.exists?(profile_id: @member.id)

        result = ::Shares::Create.call(@target, with: @member, by: profile)
        raise ActiveRecord::RecordInvalid, result.share if result.failure?

        [ entry("shared", result.share) ]
      end

      def shares = @target.shares
      def person = Members.new(profile).label(@member)
    end
  end
end
