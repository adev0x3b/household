# frozen_string_literal: true

require "test_helper"
require "i18n/tasks"

# Every word on screen goes through t() and exists in English and Italian
# (config/i18n-tasks.yml says what the scanner can't see on its own, and
# who asks for it). The files keep their order by feature, so they are not
# normalized.
class I18nTest < ActiveSupport::TestCase
  setup { @i18n = I18n::Tasks::BaseTask.new }

  test "every key the code asks for exists in every language" do
    missing = @i18n.missing_keys
    assert_empty missing, "#{missing.leaves.count} keys are missing; `bundle exec i18n-tasks missing` lists them"
  end

  test "every key in the locale files is asked for" do
    unused = @i18n.unused_keys
    assert_empty unused, "#{unused.leaves.count} keys are unused; `bundle exec i18n-tasks unused` lists them " \
                         "(a key the code builds from a name goes in config/i18n-tasks.yml, with who asks for it)"
  end

  # Read from the app's own files, not through I18n: another gem's locale
  # file on the load path (ice_cube carries Italian month names) would
  # otherwise stand in for a missing key, until that gem stops shipping it.
  test "every language has the words Rails itself says in its own files: validation messages, dates, numbers" do
    leaves = ->(tree, path = []) { tree.flat_map { |key, value| value.is_a?(Hash) ? leaves.(value, path + [ key ]) : [ (path + [ key ]).join(".") ] } }
    rails = %w[activesupport activemodel activerecord actionview].flat_map { Dir[Gem.loaded_specs[_1].full_gem_path + "/lib/**/locale/en.yml"] }
      .flat_map { leaves.(YAML.load_file(_1)["en"]) }.uniq

    (I18n.available_locales - [ :en ]).each do |locale|
      own = Dir[Rails.root.join("config/locales/{,*.}#{locale}.yml")].flat_map { leaves.(YAML.load_file(_1).fetch(locale.to_s)) }
      missing = rails - own
      assert_empty missing, "#{locale} lacks Rails' own #{missing.first(5).join(", ")}…; English has them from Rails, so add them to #{locale}.yml"
    end
  end

  # The models people fill in on a form, and what of theirs the app sets
  # itself (never in a message a person reads). A day's form also says
  # back its series' errors (Occurrences::FormSave), so Event's fields are
  # named as the day's. The rows a form takes in its lists are found from
  # the forms themselves.
  FORMS = %w[
    Occurrence Event
    Ingredient IngredientPurchase GroceryList GroceryListItem Recipe
    Supply Analyte ReferenceRange Unit Collection Book Upload UploadLink EventReminder
    Message MessageReaction Conversation Household Profile Platform::Setting Assistant::Setting LexiconLanguage LexiconEvalCase
  ].freeze
  SET_BY_THE_APP = %w[
    profile profile_id event event_id occurrence household household_id type kind status token_digest key byte_size received_bytes
    grocery_list recipe medication_details meal_details lexicon_language conversation sender client_id message direct_key slug locale role
    assistant_chat upload currency
  ].freeze

  test "a form that didn't save names its fields in every language, never in Rails' English guess" do
    unnamed = forms_with_their_rows.flat_map do |model|
      names = model == Event ? Occurrence : model
      fields = model.validators.flat_map(&:attributes).map(&:to_s).uniq - SET_BY_THE_APP
      I18n.available_locales.flat_map do |locale|
        fields.reject { |field| named?(names, field, locale) }.map { |field| "#{model.name}##{field} (#{locale})" }
      end
    end

    assert_empty unnamed, "add activerecord.attributes.<model>.<field> to every locale file, worded as the form's label"
  end

  # An error on a row is told with the name of its list ("Ingredients, row 2: …").
  test "every list a form takes rows for is named in every language" do
    unnamed = forms_with_their_rows.flat_map do |model|
      lists = model.nested_attributes_options.keys.select { model.reflect_on_association(_1).collection? }
      I18n.available_locales.flat_map do |locale|
        lists.reject { |list| named?(model, list, locale) }.map { |list| "#{model.name}##{list} (#{locale})" }
      end
    end

    assert_empty unnamed, "add activerecord.attributes.<model>.<list> to every locale file, worded as the form's heading for it"
  end

  test "each language fills in the same %{placeholders}" do
    inconsistent = @i18n.inconsistent_interpolations
    assert_empty inconsistent, "#{inconsistent.leaves.count} keys differ in their %{placeholders}; " \
                               "`bundle exec i18n-tasks check-consistent-interpolations` lists them"
  end

  private

  def forms_with_their_rows
    Rails.application.eager_load!
    with_rows(FORMS.map(&:constantize) + Event.types.map(&:details_class))
  end

  def with_rows(models)
    rows = models.flat_map { |model| model.nested_attributes_options.keys.map { model.reflect_on_association(_1).klass } } - models
    rows.empty? ? models : with_rows(models + rows.uniq)
  end

  def named?(model, field, locale)
    model.lookup_ancestors.any? { I18n.exists?("activerecord.attributes.#{_1.model_name.i18n_key}.#{field}", locale) }
  end
end
