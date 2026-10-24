# frozen_string_literal: true

# A file's icon, by what it is (Upload#kind), on its row and its page.
class Views::Uploads::Icon < Views::Base
  BY_KIND = {
    image: "fa-file-image", video: "fa-file-video", audio: "fa-file-audio", pdf: "fa-file-pdf", archive: "fa-file-zipper",
    spreadsheet: "fa-file-excel", presentation: "fa-file-powerpoint", document: "fa-file-word", text: "fa-file-lines", file: "fa-file"
  }.freeze

  def initialize(upload)
    @upload = upload
  end

  def view_template = render Components::Icon.new(BY_KIND.fetch(@upload.kind))
end
