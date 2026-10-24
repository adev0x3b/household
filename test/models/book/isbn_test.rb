# frozen_string_literal: true

require "test_helper"

class Book::IsbnTest < ActiveSupport::TestCase
  test "an ISBN-13 comes out as its digits, hyphens and spaces gone" do
    assert_equal "9780306406157", Book::Isbn.normalize("978-0-306-40615-7")
    assert_equal "9780306406157", Book::Isbn.normalize(" 978 0306 406157 ")
  end

  test "an ISBN-10 becomes the ISBN-13, the X check digit included" do
    assert_equal "9780306406157", Book::Isbn.normalize("0-306-40615-2")
    assert_equal "9780807014295", Book::Isbn.normalize("080701429X")
    assert_equal "9780807014295", Book::Isbn.normalize("080701429x")
  end

  test "digits that don't check out are nothing" do
    assert_nil Book::Isbn.normalize("9780306406158")
    assert_nil Book::Isbn.normalize("0306406153")
    assert_nil Book::Isbn.normalize("1234567890123")   # not 978/979
    assert_nil Book::Isbn.normalize("51299")           # the price add-on
    assert_nil Book::Isbn.normalize("")
    assert_nil Book::Isbn.normalize(nil)
  end

  test "valid13? knows the prefix and the checksum" do
    assert Book::Isbn.valid13?("9780441478125")
    assert_not Book::Isbn.valid13?("9780441478126")
    assert_not Book::Isbn.valid13?("9770441478125")
  end
end
