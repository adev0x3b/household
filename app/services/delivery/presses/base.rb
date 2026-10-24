# frozen_string_literal: true

module Delivery
  module Presses
    # A press is a form object: the modal shows it, and saving it either
    # refuses with errors the admin can fix or records and dispatches the
    # press. GitHub's own refusal is raised, since no field would fix it.
    class Base
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :destination, :string
      attribute :version, :string
      attribute :ref, :string
      attribute :fresh, :boolean
      attribute :reason, :string
      attribute :typed, :string
      attribute :password, :string

      attr_reader :pipeline, :request

      def initialize(pipeline:, sudo:, **attributes)
        @pipeline = pipeline
        @sudo = sudo
        super(**attributes)
      end

      class << self
        # The word a link, the modal and the request use for this kind of press.
        def kind = raise(NotImplementedError)
        # The request's action: the kind, unless Active Record owns the word.
        def action = kind.to_s
        # The workflow a press of this kind starts on GitHub.
        def workflow = Github::WORKFLOW
        # Done the moment GitHub takes it, with no run to follow.
        def instant? = false

        # The run GitHub lists for a request of this kind, once it is there.
        # The Deploy workflow puts the request's "#<id>" in each run's name.
        def find_run(request)
          Github.workflow_runs(limit: 10).find { _1.title.include?("##{request.id}") }
        end
      end

      def kind = self.class.kind
      def action = self.class.action
      # Where the admin can follow the press before its run is found.
      def workflow_url = Deployment.github_url("actions", "workflows", self.class.workflow, repository: Github.repository_of(self.class.workflow))
      def icon = raise(NotImplementedError)
      # What can't be undone with a click: a red button, and the version typed back.
      def danger? = false
      def typed? = danger?
      def reason_required? = false
      # Changes production, or the whole pipeline: the password, unless typed lately.
      def gated? = false
      def password? = gated? && !@sudo.active?
      def blocked? = false

      # The destination it acts on, when it is one of the pipeline's.
      def environment = destination && pipeline.environment(destination)
      def phrase = version&.first(7)

      def save(by:)
        check
        errors.add(:base, :wrong_password) if password? && !@sudo.verify(password)
        return false if errors.any?

        @request = Request.create!(profile: by, action: action, reason: reason.presence, **request_attributes)
        dispatch
        settle_or_watch
        true
      rescue Github::Error => e
        @request&.update!(status: :failed, summary: e.message, finished_at: Time.current)
        raise
      end

      private

      # What the subclass records on the request besides who, the action and why.
      def request_attributes = {}

      # Starts on GitHub what the press asks for, once its request is saved.
      def dispatch = raise(NotImplementedError)

      def run_workflow(**inputs) = Github.dispatch(action: action, reason: @request.reason_for_github, **inputs)

      # What refuses the press, as errors on base. Subclasses add their own after `super`.
      def check
        errors.clear
        errors.add(:base, :reason_required) if reason_required? && reason.blank?
        errors.add(:base, :typed_mismatch, phrase: phrase) if typed? && version.present? && typed.to_s.strip.downcase != phrase.downcase
      end

      def settle_or_watch
        if self.class.instant?
          @request.update!(status: :succeeded, finished_at: Time.current)
        else
          WatchJob.set(wait: WatchJob::EVERY).perform_later(@request.id)
        end
      end
    end
  end
end
