# Lexicon fixtures

Real lines from kaikki.org's Wiktionary extracts, trimmed to the fields the importer reads.

- `italian_sample.jsonl.gz`, `english_sample.jsonl.gz`: every noun the supply-name benchmark
  (`test/support/supply_names_benchmark.rb`) and the `config/lexicons.yml` checks use. Rebuild after
  changing either, from full downloads:

      bin/rails runner script/lexicon_fixture.rb italian.jsonl.gz english.jsonl.gz

- `broken_sample.jsonl.gz`: the Italian sample plus malformed lines, for trying a failed import by hand:

      SOURCE=test/fixtures/files/lexicon/broken_sample.jsonl.gz bin/rails "lexicon:import[it]"

- `kaikki_index.html`: not kaikki.org's page but a small one written by hand in the shape of its index,
  with the cases `Lexicon::Catalog.parse` must handle.
