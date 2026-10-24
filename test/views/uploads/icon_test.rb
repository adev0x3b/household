# frozen_string_literal: true

require "test_helper"

class Views::Uploads::IconTest < ActiveSupport::TestCase
  test "every kind of file has its icon, and a file of no known kind the plain one" do
    assert_equal [ *Upload::KINDS.keys, :file ].sort, Views::Uploads::Icon::BY_KIND.keys.sort

    assert_includes Views::Uploads::Icon.new(uploads(:lease)).call, "fa-file-pdf"
    assert_includes Views::Uploads::Icon.new(Upload.new).call, %(class="fa-solid fa-file")
  end
end
