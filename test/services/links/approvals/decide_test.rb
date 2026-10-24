# frozen_string_literal: true

require "test_helper"

# Why a request approved but not carried out failed
# (Links::Approvals::Decide.failure_of): a reason each reader's page words.
class Links::Approvals::DecideTest < ActiveSupport::TestCase
  def failure_of(error) = Links::Approvals::Decide.failure_of(error)

  test "an approval that couldn't be carried out keeps why, as a reason" do
    invalid = Task.new(title: "").tap(&:validate)

    assert_equal :changed, failure_of(ActiveRecord::RecordInvalid.new(invalid))
    assert_equal :not_allowed, failure_of(Pundit::NotAuthorizedError.new)
    assert_equal :gone, failure_of(ActiveRecord::RecordNotFound.new)
    assert_equal :gone, failure_of(Links::Approvals::Apply::Failed.new(:gone))
  end

  test "every reason is worded in every language" do
    LinkApproval.failures.each_key do |failure|
      I18n.available_locales.each do |locale|
        assert I18n.exists?("links.approvals.failures.#{failure}", locale), "#{failure} has no words in #{locale}"
      end
    end
  end
end
