# frozen_string_literal: true

# Whether the model is writing a language's eval cases, and why it last
# failed — state the admin page shows, kept here rather than in the cache
# (the page mustn't depend on a cache being set up).
class AddCaseWritingStateToLexiconLanguages < ActiveRecord::Migration[8.1]
  def change
    add_column :lexicon_languages, :cases_writing_since, :datetime
    add_column :lexicon_languages, :cases_error, :text
  end
end
