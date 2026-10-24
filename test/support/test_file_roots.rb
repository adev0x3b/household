# frozen_string_literal: true

# Where the files a test writes go: tmp/test-files/<worker>, emptied before
# every test — as each test's rows go with its transaction. Never storage/,
# where a development copy keeps real uploads and downloaded dictionaries,
# and never another worker's directory: two workers writing the same
# fixture upload's file would collide.
module TestFileRoots
  def self.worker=(id)
    @worker = id.to_s
  end

  def self.reset
    root = Rails.root.join("tmp/test-files", @worker || "main")
    FileUtils.rm_rf(root)
    Uploads::Storage.root = root.join("uploads")
    Lexicon::Downloads.dir = root.join("lexicons")
  end
end
