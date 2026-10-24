# frozen_string_literal: true

require "test_helper"

# The extract a download keeps (Lexicon::Downloads): whole or not at all,
# and an import can read it again instead of downloading.
class Lexicon::DownloadsTest < ActiveSupport::TestCase
  setup { Lexicon::Downloads.dir = (@dir = Dir.mktmpdir) }

  teardown do
    Lexicon::Downloads.dir = nil
    FileUtils.rm_rf(@dir)
  end

  # A download from kaikki.org, played from a fixture's bytes (cut short with `bytes`).
  def download(bytes: nil)
    whole = file_fixture("lexicon/italian_sample.jsonl.gz").binread
    data = bytes ? whole[0, bytes] : whole
    source = Lexicon::Source.new(url: "https://kaikki.org/dictionary/Italian/x.jsonl.gz", store_to: Lexicon::Downloads.path("it"))
    source.define_singleton_method(:each_chunk) do |&block|
      @expected_bytes = whole.bytesize
      data.scan(/.{1,512}/m).each { block.call(_1) }
    end
    source
  end

  test "a complete download is kept, byte for byte" do
    lines = download.to_enum(:each_line).to_a

    assert_operator lines.size, :>, 40
    assert_equal file_fixture("lexicon/italian_sample.jsonl.gz").binread, Lexicon::Downloads.path("it").binread
    assert_equal Lexicon::Downloads.path("it").size, Lexicon::Downloads.info("it")[:size]
  end

  test "a download cut short keeps nothing — not even its .part" do
    assert_raises(Lexicon::Source::Error) { download(bytes: 1000).to_enum(:each_line).to_a }

    assert_nil Lexicon::Downloads.info("it")
    assert_empty Dir.children(@dir)
  end

  test "an import reads the kept file again when asked not to download" do
    FileUtils.cp(file_fixture("lexicon/italian_sample.jsonl.gz"), Lexicon::Downloads.path("it"))
    italian_cases!
    import = Lexicon::Import.call(lexicon_language("it"), download: false, force: true, agent: :skip)

    assert_predicate import, :active?, import.error
    assert_equal Lexicon::Downloads.path("it").to_s, import.source_url
  end

  test "asked not to download with no kept file, it fails at the source step saying so" do
    import = Lexicon::Import.call(lexicon_language("it"), download: false, force: true, agent: :skip)

    assert_predicate import, :failed?
    assert_equal "source", import.failed_step
    assert_match "no file of it has been downloaded yet", import.error
  end
end
