# frozen_string_literal: true

# What a destination may be asked by bin/provision, and what every reader of
# the environment defaults when a destination says nothing: config/deploy.yml
# and config/deploy.<destination>.yml for a Kamal destination, and the Deploy
# workflow passing a GitHub environment's variables and secrets through
# (.github/workflows/kamal.yml, .kamal/secrets-common), and compose.yml for a
# copy run without the pipeline. One list, so none of them drifts:
# test/lib/provision holds each to it. Platform and Assistant
# read the names; .env.example describes them for a person; the demo's are
# also DemoBuilders::DEMO_SETTINGS in the tests.
module Provision
  module Settings
    DESTINATIONS = %w[production staging demo dev].freeze
    DEMO_ACCOUNTS = "alex.demo,sam.demo,robin.demo"

    # One setting: its variable's name; how an answer is read (switch, count,
    # size, memory, list, choice, text, secret); the question asked; its
    # default, and the destinations whose default differs; a choice's
    # options; whether it is a secret (hidden when typed, a GitHub secret
    # rather than a variable); the destinations it is asked for (nil: every
    # one); whether only the pipeline has a use for it; whether the app reads
    # it, or only config/deploy*.yml does, to size the containers.
    Setting = Data.define(:name, :kind, :question, :default, :overrides, :choices, :secret, :asked_on, :pipeline_only, :app) do
      def default_for(destination) = overrides.fetch(destination, default)
      def secret? = secret
      def pipeline_only? = pipeline_only
      def app? = app
      def asked_on?(destination) = asked_on.nil? || asked_on.include?(destination)
    end

    def self.setting(name, kind, question, default, overrides = {}, choices: nil, secret: false, asked_on: nil, pipeline_only: false, app: true)
      Setting.new(name:, kind:, question:, default:, overrides: overrides.transform_keys(&:to_s).freeze, choices:, secret:, asked_on:, pipeline_only:, app:)
    end
    private_class_method :setting

    CATALOGUE = [
      setting("ASSISTANT", :switch, "The assistant", "on"),
      setting("UPLOADS", :switch, "Files: uploads and public links", "on", { demo: "off" }),
      setting("PICTURES", :switch, "Pictures in messages, photos to the assistant", "on", { demo: "off" }),
      setting("INVITATIONS", :switch, "Members inviting people (the admin always can)", "on", { demo: "off" }),
      setting("PUSH_NOTIFICATIONS", :switch, "Push notifications to devices", "on", { demo: "off" }),
      setting("ASSISTANT_MESSAGES_PER_DAY", :count, "A household's messages to the assistant in a day (blank: no limit)", "", { demo: "30" }),
      setting("BOOK_LOOKUPS_PER_DAY", :count, "A household's Open Library lookups in a day (blank: no limit)", "", { demo: "50" }),
      setting("FILES_QUOTA", :size, "What a household may keep in Files", "50GB", { staging: "512MB", dev: "512MB", demo: "64MB" }),
      setting("OPEN_ACCOUNTS", :list, "The accounts anyone enters without a password", "", { dev: DEMO_ACCOUNTS, demo: DEMO_ACCOUNTS },
              asked_on: %w[dev demo]),
      setting("ASSISTANT_PROVIDER", :choice, "The assistant's provider", "ollama", choices: %w[ollama anthropic openai]),
      setting("ASSISTANT_MODEL", :text, "The assistant's model", "qwen3:8b"),
      setting("OLLAMA_BASE_URL", :text, "Ollama's address, as a container reaches it", "http://host.docker.internal:11434"),
      setting("ANTHROPIC_API_KEY", :secret, "The Anthropic API key", "", secret: true),
      setting("OPENAI_API_KEY", :secret, "The OpenAI API key", "", secret: true),
      setting("GOOGLE_BOOKS_API_KEY", :secret, "The Google Books API key, the bookshelf's second source", "", secret: true),
      setting("DEMO_PASSWORD", :secret, "The open accounts' password", "demo-household", secret: true, asked_on: %w[dev demo]),
      setting("DEPLOY_DISPATCH_TOKEN", :secret, "The GitHub token behind the delivery console's buttons", "", secret: true,
                                                                                                              asked_on: %w[production staging], pipeline_only: true),
      # The most each container may take of the machine (blank: no cap), so
      # destinations sharing a machine can't starve each other.
      setting("WEB_MEMORY", :memory, "The most memory the web container may take (blank: the destination's default)", "", { staging: "1GB", dev: "1GB", demo: "1GB" },
              pipeline_only: true, app: false),
      setting("JOB_MEMORY", :memory, "The most memory the job container may take (blank: the destination's default)", "", { staging: "1GB", dev: "1GB", demo: "1GB" },
              pipeline_only: true, app: false),
      setting("DB_MEMORY", :memory, "The most memory Postgres may take (blank: the destination's default)", "", pipeline_only: true, app: false)
    ].freeze

    def self.all = CATALOGUE
    def self.names = CATALOGUE.map(&:name)
    def self.find(name) = CATALOGUE.find { _1.name == name } || raise(KeyError, "no setting named #{name}")
    # What the app is passed, in plain or as a key; and what sizes its containers.
    def self.clear = CATALOGUE.select { _1.app? && !_1.secret? }
    def self.secret = CATALOGUE.select(&:secret?)
    def self.caps = CATALOGUE.reject(&:app?)
    # What compose.yml passes to a copy run without the pipeline.
    def self.compose = CATALOGUE.reject(&:pipeline_only?)

    # What bin/provision asks for a destination.
    def self.for(destination) = CATALOGUE.select { _1.asked_on?(destination) }

    # Every setting's default for a destination, by name.
    def self.defaults(destination) = CATALOGUE.to_h { [ _1.name, _1.default_for(destination) ] }
  end
end
