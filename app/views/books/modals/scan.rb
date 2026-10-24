# frozen_string_literal: true

# The scanner: the camera in a viewfinder (barcode_scanner_controller.js
# reads the ISBN's EAN-13 off it), a photo of the barcode when the camera
# can't stream, and always the ISBN typed by hand. All three end in the
# same form: a POST to BooksController#lookup, which answers with the book's
# form filled in from the catalogues (Books::Lookup).
class Views::Books::Modals::Scan < Views::Base
  def initialize(wasm_url:)
    @wasm_url = wasm_url
  end

  def view_template
    render Components::Modal.new(size: :small, section: :bookshelf) do |modal|
      modal.modal_header(title: t("books.scan.title"), subtitle: t("books.scan.subtitle"), icon: "fa-barcode")

      # The scanner is the form itself, so a barcode it reads submits the
      # same lookup as the footer's button.
      modal.modal_form(url: lookup_books_path, method: :post, data: scanner_data) do
        modal.modal_body do
          div(class: "scanner") do
            camera
            photo
            isbn_field
          end
        end
        modal.modal_footer do
          div(class: "modal__footer-main") do
            button(type: "submit", class: "modal__btn modal__btn--primary") { t("books.scan.look_up") }
          end
        end
      end
    end
  end

  private

  def scanner_data
    {
      controller: "barcode-scanner", turbo_stream: true, turbo_frame: "_top",
      barcode_scanner_wasm_url_value: @wasm_url, barcode_scanner_messages_value: messages.to_json
    }
  end

  def messages
    %w[starting loading aim found no_camera denied none_in_photo].index_with { |key| t("books.scan.#{key}") }
  end

  def camera
    div(class: "scanner__viewport", data: { barcode_scanner_target: "viewport" }) do
      video(class: "scanner__video", playsinline: true, muted: true, autoplay: true, data: { barcode_scanner_target: "video" })
      div(class: "scanner__viewfinder", aria: { hidden: "true" })
    end
    p(class: "scanner__status", role: "status", aria: { live: "polite" }, data: { barcode_scanner_target: "status" }) { t("books.scan.starting") }
  end

  # A photo of the barcode: offered when the camera can't stream here.
  def photo
    div(class: "scanner__fallback", hidden: true, data: { barcode_scanner_target: "fallback" }) do
      label(class: "button scanner__photo") do
        render Components::Icon.new("fa-camera")
        span { t("books.scan.photo") }
        input(type: "file", accept: "image/*", capture: "environment", class: "is-sr-only", data: { action: "change->barcode-scanner#decodePhoto" })
      end
    end
  end

  def isbn_field
    render Components::Field.new(label: t("books.scan.isbn_label"), control_id: "scanner_isbn") do
      input(type: "text", id: "scanner_isbn", name: "isbn", class: "input", inputmode: "numeric", autocomplete: "off",
            placeholder: t("books.scan.isbn_placeholder"), data: { barcode_scanner_target: "isbn" })
    end
  end
end
