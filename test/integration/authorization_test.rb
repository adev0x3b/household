# frozen_string_literal: true

require "test_helper"

# The safety net (ApplicationController): every action asks Pundit or says
# why it doesn't, and a refused request is answered without replaying it.
class AuthorizationTest < ActionDispatch::IntegrationTest
  # Every action that skips Pundit, as the controllers declare it. Adding one
  # means adding it here, with its reason: a reviewer sees each exemption.
  EXEMPT = %w[
    AttentionResolutionsController#create
    CalendarController#show
    DemosController#create DemosController#show
    HomeController#report HomeController#show
    LinksController#index
    LocalesController#update
    PwaController#manifest PwaController#offline PwaController#service_worker
    SetupAssistantModelsController#show
    SetupAssistantTestsController#create
    SetupCodesController#create
    SetupController#create SetupController#show
    TimeZonesController#update
    UploadLinks::PublicController#create UploadLinks::PublicController#file UploadLinks::PublicController#show
  ].freeze

  class ProbesController < ApplicationController
    def forgets = head(:ok)

    def refuses
      authorize Household.new(name: "Elsewhere"), :show?
    end
  end

  test "the exemptions are exactly these, each with its reason" do
    Rails.application.eager_load!
    declared = ApplicationController.descendants.flat_map do |controller|
      controller.authorization_exemptions.map { |action, reason| [ "#{controller.name}##{action}", reason ] }
    end.uniq.to_h

    assert_equal EXEMPT, declared.keys.reject { _1.start_with?("AuthorizationTest::") }.sort
    assert declared.values.all?(&:present?), "every exemption says why"
  end

  test "an action that never asks Pundit fails" do
    sign_in profiles(:alice)
    with_routing do |routes|
      routes.draw { get "probe/forgets", to: "authorization_test/probes#forgets" }

      assert_raises(Pundit::AuthorizationNotPerformedError) { get "/probe/forgets" }
    end
  end

  test "a refused page goes back by 303; a refused Turbo Stream request gets 403 and a toast" do
    sign_in profiles(:alice)
    with_routing do |routes|
      routes.draw { patch "probe/refuses", to: "authorization_test/probes#refuses" }

      patch "/probe/refuses", headers: { "HTTP_REFERER" => "http://www.example.com#{Rails.configuration.x.mount_path}/household" }
      assert_response :see_other

      patch "/probe/refuses", as: :turbo_stream
      assert_response :forbidden
      assert_toast I18n.t("pundit.not_authorized")
    end
  end
end
