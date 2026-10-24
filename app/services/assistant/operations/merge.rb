# frozen_string_literal: true

module Assistant
  module Operations
    # Merges one analyte into another ("Vit D and Vitamin D are the same"),
    # keeping the old name as an alias so a report that says it again finds
    # the kept one. It rewrites history, so like a deletion it waits for the
    # user's button and can't be undone.
    class Merge < Base
      def phase = :changing
      def risky? = true

      def check
        fail!("merge is only for analytes") unless resource.mergeable?
        @from, @into = pinned? ? pinned_records : [ analyte(ref, "ref"), analyte(fields["into"], "into") ]
        fail!("#{@from.name} and #{fields["into"]} are the same analyte already") if @from == @into
        [ [ @from, :destroy? ], [ @into, :update? ] ].each { |record, action| Pundit.authorize(profile, record, action) }

        @dropped = @from.reference_ranges.includes(:unit).select { |range| taken?(range) }
        @notes << "#{@into.name} already has a reference range for #{@dropped.map { |r| "#{r.unit.name} (#{r.sex})" }.to_sentence}; #{@from.name}'s is dropped" if @dropped.any?
      end

      def checked_records = [ @from, @into ].compact

      def apply!(applier)
        applier.not_undoable!
        Analyte.transaction do
          moved = LabTestResultEntry.where(analyte: @from).update_all(analyte_id: @into.id)
          @from.reference_ranges.each { |range| taken?(range) ? range.destroy! : range.update!(analyte: @into) }
          names = [ @from.name, *@from.aliases.map(&:name) ]
          @from.aliases.destroy_all
          @from.reload.destroy!
          names.reject { |name| name.casecmp?(@into.name) }.each { |name| @into.aliases.find_or_create_by!(name: name) }
          [ entry("merged", @into, from: @from.name, values: moved) ]
        end
      end

      def label
        return super unless @from && @into

        I18n.t("assistant.operations.merge_pair", from: @from.name, into: @into.name)
      end

      private

      def taken?(range) = ReferenceRange.exists?(analyte_id: @into.id, unit_id: range.unit_id, sex: range.sex)

      # By id or name (exact, or a close spelling), never a search, which
      # finds "Vitamin D" for "Vit D" too.
      def analyte(words, field)
        fail!("say which analyte (#{field})") if words.blank?
        analytes = profile.analytes
        return analytes.find(words) if words.to_s.match?(/\A\d+\z/)

        NameMatch.find(analytes, words) ||
          fail!("no analyte called #{words}; the user's include #{analytes.order(:name).limit(30).pluck(:name).to_sentence}")
      end
    end
  end
end
