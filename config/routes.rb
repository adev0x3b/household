# frozen_string_literal: true

Rails.application.routes.draw do
  # Every route lives under the app's mount path (config.x.mount_path).
  scope path: Rails.configuration.x.mount_path.delete_prefix("/").presence do
    # Invite only: no sign-up. Of devise_invitable's routes only accepting an
    # invitation is kept; inviting is /household_invitations. Of Devise's
    # password routes only setting one from a link (Profiles::PasswordLink):
    # nothing asks for one by email.
    devise_for :profiles, controllers: { sessions: "profiles/sessions" }, skip: [ :invitations, :passwords ]
    devise_scope :profile do
      get "profiles/invitation/accept", to: "profiles/invitations#edit", as: :accept_profile_invitation
      match "profiles/invitation", to: "profiles/invitations#update", via: %i[put patch], as: :profile_invitation
      get "profiles/password/edit", to: "profiles/passwords#edit", as: :edit_profile_password
      match "profiles/password", to: "profiles/passwords#update", via: %i[put patch], as: :profile_password
    end

    # Sharing a thing with a housemate (Shareable): one SharesController
    # under each kind, which the route names (a parameter can't).
    concern :shareable do |options|
      resources :shares, only: %i[new create destroy], defaults: { shareable: options.fetch(:type) }
    end

    # The demo household's front door (no credentials) and its banner's "see it as…".
    get "demo", to: "demos#show", as: :demo
    post "demo", to: "demos#create"

    # The first account on a fresh database (SetupController); gone once anyone
    # exists. It opens to a browser that has given the copy's setup code; its
    # assistant step tries the connection typed and lists the provider's models.
    resource :setup, only: %i[show create], controller: "setup" do
      resource :code, only: :create, controller: "setup_codes"
      resource :assistant_test, only: :create, controller: "setup_assistant_tests"
      resource :assistant_models, only: :show, controller: "setup_assistant_models"
    end

    # The current profile's household: its people, and inviting more of them.
    resource :household, only: :show

    # Links between housemates: asking, accepting, ending one (declined or
    # taken back while it waits, unlinked once accepted), what each lets the
    # other do with one kind of their items (a link's grants, by kind, so a
    # kind with no row yet can be set too), and the changes waiting for an
    # owner's OK (link_approvals): given (consent), or dropped by the owner
    # (declined) or the asker (withdrawn).
    resources :links, only: %i[index create destroy] do
      resource :acceptance, only: :create, controller: "link_acceptances"
      resources :grants, only: :update, param: :event_type, controller: "link_grants"
    end
    resources :link_approvals, only: :destroy do
      resource :consent, only: :create, controller: "link_approval_consents"
    end
    # Someone is invited under a household (the viewer's own, or any for the
    # admin); the invitation is then its own: taken back, or given a new
    # link (a renewal). A member is removed, or given a link to set a
    # password, by their own id.
    resources :households, only: [] do
      resources :invitations, only: %i[new create], controller: "household_invitations"
    end
    resources :household_invitations, only: :destroy do
      resources :renewals, only: :create, controller: "household_invitation_renewals"
    end
    resources :household_members, only: :destroy do
      resources :password_links, only: :create, controller: "household_member_password_links"
    end

    # The home dashboard: an overview, and one page per section of the
    # household (Views::Home::Pages; a name no page has is not found). A
    # page's reports load lazily, one frame each. "Needs
    # attention" is settled from its list: a series' days still to do
    # marked skipped, or the whole list of the page the press was on.
    get "home/:section", to: "home#show", as: :home_section
    get "home/:section/reports/:name", to: "home#report", as: :home_report
    post "home(/:section)/attention/resolutions", to: "attention_resolutions#create", as: :attention_resolutions
    resource :calendar, only: :show, controller: :calendar
    # A new series of each kind (Event.types): its form, for the day the "+"
    # was pressed, and its creation (TasksController, MedicationsController, …).
    Event::TYPES.each { |type| resources type.underscore.pluralize.to_sym, only: %i[new create] }

    # A day of any series, saved or not yet, named by its series and date and,
    # for a series taken several times a day, its time (`?time=`): its form,
    # its deletion (one dose of it, the day, or `scope=series`), whether it
    # is done, a resource of its own that a press puts there or takes away,
    # and its status, set in one press that says which.
    resources :events, only: [] do
      resources :days, only: %i[edit update destroy], param: :date do
        member do
          resource :completion, only: %i[create destroy], controller: "day_completions", as: :day_completion
          resource :status, only: :update, controller: "day_statuses", as: :day_status
        end
      end
      concerns :shareable, type: "Event"
    end

    # A few series shared as one thing (a therapy, a job hunt), per section.
    resources :collections do
      concerns :shareable, type: "Collection"
    end

    # What is only ever made under its parent (an analyte's reference range,
    # a supply's or an ingredient's purchase) is listed, offered and made
    # under the parent's address, and is then its own record by its own id.
    resources :analytes do
      resources :reference_ranges, only: %i[new create]
    end
    resources :reference_ranges, only: %i[edit update destroy]

    resources :supplies, except: :show do
      resources :purchases, only: %i[index new create], controller: "supply_purchases" # the index is the supply's history
    end
    resources :supply_purchases, only: %i[edit update destroy]

    resources :ingredients, except: :show do
      resources :purchases, only: %i[index new create], controller: "ingredient_purchases"
    end
    resources :ingredient_purchases, only: %i[edit update destroy]

    resources :recipes do
      concerns :shareable, type: "Recipe"
    end

    # A grocery list is shopped and then finished (its completion), and an
    # item on it is ticked off (its check) or put back.
    resources :grocery_lists do
      resource :completion, only: %i[create destroy], controller: "grocery_list_completions"
      resources :grocery_list_items, only: [ :create, :edit, :update, :destroy ], shallow: true do
        resource :check, only: %i[create destroy], controller: "grocery_list_item_checks"
      end
      concerns :shareable, type: "GroceryList"
    end

    # The bookshelf: a cover grid per member, scanned in or typed, shared
    # whole or one book at a time. A book's status is set in one tap on its
    # card or page. A lookup fills the form from the catalogues by its
    # ISBN: it is sent from inside the form, with the form's own method, so
    # a new book's is a POST and an edit's a PATCH of the book's address.
    resources :books do
      resource :status, only: :update, controller: "book_statuses"
      patch :lookup, on: :member
      collection do
        get :scanner # the barcode scanner modal
        post :lookup
      end
      concerns :shareable, type: "Book"
    end
    # The signed-in person's whole shelf, shared as one thing.
    resource :bookshelf, only: [] do
      concerns :shareable, type: "Bookshelf"
    end

    # Files: big files kept on the server, uploaded in chunks, shared with a
    # housemate or by a public link anyone can use. That link's page is short
    # (/s/:token), for whoever holds it: no account, so a controller of its own.
    resources :uploads, path: "files" do
      resources :chunks, only: :create, controller: "upload_chunks"       # the next chunk, raw, at the Upload-Offset header
      resources :downloads, only: :create, controller: "upload_downloads" # a press: on the trail, then the file's address
      member do
        get :file                   # the bytes, which a download cut short asks again for
        get :progress               # JSON: how far an upload has got (the page resumes from it)
      end
      resources :upload_links, only: %i[new create destroy], shallow: true
      concerns :shareable, type: "Upload"
    end
    get "s/:token", to: "upload_links/public#show", as: :public_upload_link
    post "s/:token", to: "upload_links/public#create"
    get "s/:token/file", to: "upload_links/public#file", as: :public_upload_link_file

    # Messages: the household's own conversation and one per pair of housemates
    # (the household's made when it is first looked for, a pair's by a press
    # naming the housemate), their messages, pictures and emoji reactions.
    # The page says what the reader has seen with a read receipt.
    resources :conversations, only: %i[index show create edit update] do
      resource :read_receipt, only: :create, controller: "conversation_read_receipts"
      get :older, on: :member # ?before=<message id>: the page before
      resources :messages, only: %i[create destroy], shallow: true do
        resource :reaction, only: %i[create destroy], controller: "message_reactions"
        # A picture, to the people in the conversation only: the bubble's copy, and the one sent.
        resources :pictures, only: :show, controller: "message_pictures", shallow: false do
          get :original, on: :member
        end
      end
    end

    # A deploy waits for this to answer 200 before a new version takes
    # traffic. It answers 500 when the app couldn't boot.
    get "up" => "rails/health#show", as: :rails_health_check

    # The installed app (PWA): its manifest, service worker and offline page.
    get "manifest.webmanifest", to: "pwa#manifest", as: :pwa_manifest
    get "service-worker.js", to: "pwa#service_worker", as: :pwa_service_worker
    get "offline/:locale", to: "pwa#offline", as: :pwa_offline,
                           constraints: { locale: Regexp.union(I18n.available_locales.map(&:to_s)) }

    # The navbar's bell: the list loads when it opens; new ones arrive live.
    # A notification's own address (`show`) is the link a push notification
    # carries: it only leads on. Reading one is its read receipt; "mark all
    # read" is a receipt on the whole list.
    resources :notifications, only: %i[index show] do
      resource :read_receipt, only: :create, controller: "notification_read_receipts"
    end
    resource :notification_list_read_receipt, only: :create, path: "notifications/read_receipt", controller: "notification_list_read_receipts"

    # This device's Web Push subscription ("This device" in the navbar); the
    # service worker updates it when the browser replaces it.
    resource :push_subscription, only: %i[create update destroy]

    # The browser's time zone, for reminders "3 hours before".
    resource :time_zone, only: :update

    # The language picked in the navbar; it also sets the assistant's reply language.
    resource :locale, only: :update

    # The assistant (household bookkeeper chat). /assistant opens the latest
    # conversation. The reply being written is stopped by deleting it. A
    # change set is applied by its application (a deletion it proposes is
    # confirmed here, never by it) and reverted by taking the application
    # away; one still in progress is dropped (destroy), and a draft in it
    # is reviewed in its kind's form.
    get "assistant", to: "assistant/chats#latest", as: :assistant
    namespace :assistant do
      resources :chats, only: %i[index show create edit update destroy] do
        resources :messages, only: :create
        resources :attachments, only: :show # a photo sent in it, to its owner alone
        resource :reply, only: :destroy, controller: "chat_replies"
      end
      resources :change_sets, only: :destroy do
        resource :application, only: %i[create destroy], controller: "change_set_applications"
        get :review, on: :member
      end

      # The assistant's provider, keys, model and tuning (the admin's: Admin::BaseController).
      resource :settings, only: %i[show update] do
        get :check
        post :test
        get :models
        delete "keys/:provider", action: :clear_key, as: :key, constraints: { provider: Regexp.union(Assistant::Setting::KEYED_PROVIDERS) }
      end

      # The eval dashboard (the admin's: Admin::BaseController).
      get "evals", to: "evals#index", as: :evals
      namespace :evals do
        resources :scenarios, param: :name, except: %i[show] do
          post :try, on: :collection
        end
        resources :runs, only: %i[index new create show destroy], constraints: { id: /[\w.-]+/ } do
          get :events, on: :member
          post :pause, on: :member
          post :resume, on: :member
        end
      end
    end

    # Admin-only tools: the households, the deployment, the settings, and the lexicon's languages and their imports.
    namespace :admin do
      resources :households, only: %i[index show new create]
      # Where the app runs (Admin::DeploymentsController): what this copy
      # says about itself, and the pipeline on GitHub in frames of its own
      # (Admin::DeliveriesController). A press on the pipeline is a request
      # of a kind (Admin::DeliveryRequestsController): its modal, then the press.
      resource :deployment, only: :show
      resource :delivery, only: [] do
        get :console
        get :metrics
        resources :requests, only: %i[new create], controller: "delivery_requests"
      end
      # What the admin sets for the whole app (Admin::SettingsController); forgetting one value.
      resource :settings, only: %i[show update] do
        delete "values/:key", action: :clear, as: :value, constraints: { key: Regexp.union(Platform::KEYS.map(&:to_s)) }
      end
      resources :lexicons, only: %i[index show new create], param: :language do
        # An import of the language (Admin::LexiconImportsController): its
        # modal and its start; then, once its cases are confirmed, going on
        # with it; stopping it; the assistant tests run again on the active one.
        resources :imports, only: %i[new create], controller: "lexicon_imports" do
          member do
            post :resume
            post :cancel
            post :evaluate
          end
        end
        resources :cases, only: %i[new create edit update destroy], controller: "lexicon_cases" do
          patch :confirm, on: :member
          post :write, on: :collection # the model drafts them again
        end
      end
    end

    # The admin's borrowed dashboards (Admin::EnginesController): errors
    # reported through Rails.error, and Solid Queue's jobs. Anyone else signed
    # in finds nothing there; whoever isn't is asked to sign in.
    authenticate :profile, ->(profile) { profile.admin? } do
      mount SolidErrors::Engine, at: "admin/errors", as: :admin_errors
      mount MissionControl::Jobs::Engine, at: "admin/jobs", as: :admin_jobs
    end

    root "home#show"
  end

  # Where a thing that has no page of its own is seen, so that its
  # address can be asked of it like a recipe's (`polymorphic_path`,
  # which the bell's rows use): a series on the month it starts in, a
  # shelf among the bookshelves, a dictionary and its import on the
  # admin's lexicon page, a link and a change waiting for an OK on the
  # links page. Rails takes `resolve` only outside a scope; the named routes
  # it calls carry the mount path already.
  resolve(*Event::TYPES) { |series| calendar_path(month: series.starts_on.month, year: series.starts_on.year) }
  resolve("Bookshelf") { |shelf| books_path(shelf: shelf.profile_id) }
  resolve("LexiconLanguage") { |language| admin_lexicon_path(language.code) }
  resolve("LexiconImport") { |import| admin_lexicon_path(import.language, import: import.id) }
  resolve("Link", "LinkApproval") { links_path }
end
