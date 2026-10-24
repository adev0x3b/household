# frozen_string_literal: true

# What users say against the supplies they saved, across Italian and
# English — the benchmark Lexicon::Matcher is held to (0 wrong, every
# unrelated word unmatched). Each household: its supplies, and queries => the
# supply meant (nil: none of them). Its words are also what the fixture
# extracts in test/fixtures/files/lexicon/ hold (script/lexicon_fixture.rb).
module SupplyNamesBenchmark
  HOUSEHOLDS = {
    "it" => {
      supplies: [ "Aghi", "Siringhe", "Cobalamina", "Metotrexato", "Garze", "Cerotti", "Salviette disinfettanti",
                  "Strisce reattive", "Lancette", "Fiale", "Cotone idrofilo", "Guanti in lattice", "Bende" ],
      queries: {
        "needle" => "Aghi", "needles" => "Aghi", "ago" => "Aghi", "syringe" => "Siringhe", "siringa" => "Siringhe",
        "gauze" => "Garze", "garza" => "Garze", "gauze pads" => "Garze", "plaster" => "Cerotti", "band-aid" => "Cerotti",
        "band-aids" => "Cerotti", "cerotto" => "Cerotti", "alcohol wipe" => "Salviette disinfettanti",
        "alcohol swab" => "Salviette disinfettanti", "salvietta" => "Salviette disinfettanti", "test strip" => "Strisce reattive",
        "striscia" => "Strisce reattive", "lancet" => "Lancette", "lancetta" => "Lancette", "vial" => "Fiale", "fiala" => "Fiale",
        "flaconcino" => "Fiale", "cotton wool" => "Cotone idrofilo", "cotton balls" => "Cotone idrofilo", "cotone" => "Cotone idrofilo",
        "gloves" => "Guanti in lattice", "guanto" => "Guanti in lattice", "bandage" => "Bende", "benda" => "Bende", "fascia" => "Bende",
        "thermometer" => nil, "termometro" => nil, "insulin pen" => nil, "scissors" => nil, "forbici" => nil,
        "mascherina" => nil, "face mask" => nil, "transferrin" => nil, "sharps container" => nil
      }
    },
    "en" => {
      supplies: [ "Needles", "Syringes", "Cobalamin", "Methotrexate", "Gauze", "Band-aids", "Alcohol swabs", "Test strips",
                  "Lancets", "Vials", "Cotton balls", "Latex gloves", "Bandages" ],
      queries: {
        "ago" => "Needles", "aghi" => "Needles", "siringa" => "Syringes", "siringhe" => "Syringes", "garza" => "Gauze",
        "garze" => "Gauze", "cerotto" => "Band-aids", "cerotti" => "Band-aids", "salvietta disinfettante" => "Alcohol swabs",
        "striscia reattiva" => "Test strips", "lancetta" => "Lancets", "pungidito" => "Lancets", "fiala" => "Vials",
        "cotone" => "Cotton balls", "guanti" => "Latex gloves", "benda" => "Bandages", "needle" => "Needles", "syringe" => "Syringes",
        "termometro" => nil, "forbici" => nil, "mascherina" => nil, "transferrin" => nil, "penna per insulina" => nil
      }
    }
  }.freeze

  # Every word the benchmark and config/lexicons.yml's checks use, folded.
  def self.words
    texts = HOUSEHOLDS.values.flat_map { |home| home[:supplies] + home[:queries].keys }
    texts += YAML.load_file(Rails.root.join("config/lexicons.yml")).values.flat_map { |entry| Array(entry["checks"]) }
      .flat_map { |check| check.values.flatten.map(&:to_s) }
    texts.flat_map { |text| Lexicon::Text.words(text) + [ Lexicon::Text.fold(text) ] }.to_set
  end

  # { verdict => count } and the rows, for queries answered by `pick`.
  def self.run
    rows = HOUSEHOLDS.flat_map do |_, home|
      home[:queries].map do |said, want|
        got = yield(home[:supplies], said)
        verdict = if got == want then (want ? :correct : :correct_none)
        elsif got.nil? then :missed
        else :wrong
        end
        [ said, want, got, verdict ]
      end
    end
    [ rows.group_by(&:last).transform_values(&:size), rows ]
  end
end
