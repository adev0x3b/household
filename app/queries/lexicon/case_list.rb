# frozen_string_literal: true

module Lexicon
  # A language's eval cases as its admin page lists them: what needs a look
  # first (not confirmed, or not counted), then by concept, ten to a page;
  # why each waits (Lexicon::CaseReview); and which are the language's own
  # rather than shared. Every case is read, for the reasons and the counts
  # in the section's header, but only one page is shown.
  #
  #   list = Lexicon::CaseList.new(language, import: import, page: params[:cases_page])
  #   list.shown            # => WillPaginate::Collection of LexiconEvalCase
  #   list.reason(kase)     # => :unlinked, … or nil when it counts
  class CaseList
    PER_PAGE = 10

    # import: the one the page shows; when it is a candidate not yet
    # active, the reasons are read with it in place of the active one.
    def initialize(language, import:, page:)
      @language = language
      @import = import
      @page = page
    end

    def cases = (@cases ||= @language.lexicon_eval_cases.order(:id).to_a)
    def empty? = cases.empty?
    def size = cases.size
    def unconfirmed_count = cases.count { !_1.confirmed? }

    def shown
      @shown ||= begin
        sorted = cases.sort_by { |kase| [ !kase.confirmed? || reasons.key?(kase.id) ? 0 : 1, kase.concept ] }
        last = [ (sorted.size.to_f / PER_PAGE).ceil, 1 ].max
        page = @page.to_i.clamp(1, last)
        WillPaginate::Collection.create(page, PER_PAGE, sorted.size) { |pager| pager.replace(sorted[pager.offset, pager.per_page] || []) }
      end
    end

    def reason(kase) = reasons[kase.id]

    # Written by an admin for this language alone, so it can be deleted.
    def own?(kase) = !shared_concepts.include?(kase.concept)

    private

    # Read with the import shown when it's the candidate one, else with the active imports.
    def reasons
      @reasons ||= begin
        imports = LexiconImport.active_ids
        imports = imports.merge(@language.code => @import.id) if candidate?
        imports.key?(@language.code) ? CaseReview.new(cases, @language, imports).waiting.to_h { |kase, reason| [ kase.id, reason ] } : {}
      end
    end

    def candidate? = @import.present? && !@import.active? && LexiconLemma.exists?(lexicon_import_id: @import.id)

    def shared_concepts = (@shared_concepts ||= EvalCases.concepts.map(&:concept))
  end
end
