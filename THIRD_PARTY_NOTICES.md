# Third-party notices

The application's own code is under the MIT license (`LICENSE`). This repository also carries work by others, each under its own license. It is listed here with where it lives and what it is used for. Gems and the JavaScript the gems serve (Rails, Hotwire, Bulma, Devise, Phlex, RubyLLM…) are installed by Bundler and carry their own licenses; they are not copied into this repository. The license text of each library copied here, where its own license asks for it to travel with the copy, is under `licenses/`.

## Shipped with the app

| What | Where | License |
|---|---|---|
| [Font Awesome Free](https://fontawesome.com) 6.7.2: the solid and regular icon sets, kept whole, and the app's cut of them (the icons it uses, by `bin/rails icons:subset`) | `vendor/fontawesome/`, `vendor/assets/icons/fontawesome/` | Icons CC BY 4.0, fonts SIL OFL 1.1, CSS MIT. The full terms are in `vendor/fontawesome/LICENSE.txt` |
| [Chart.js](https://www.chartjs.org) 4.5.1: its `dist/chart.js` and the chunk it imports, bundled into one module and minified with esbuild | `vendor/javascript/chart.js.js` | MIT, © Chart.js Contributors. The text is in `licenses/chart.js.txt` |
| [@kurkle/color](https://github.com/kurkle/color) 0.3.4 | `vendor/javascript/@kurkle--color.js` | MIT, © Jukka Kurkela. The text is in `licenses/kurkle-color.txt` |
| [barcode-detector](https://github.com/Sec-ant/barcode-detector) 3.2.3, the ponyfill of the browser's `BarcodeDetector` | `vendor/javascript/barcode-detector--*.js`; the ponyfill's import of its chunk is changed to a bare specifier | MIT, © Ze-Zheng Wu. The text is in `licenses/barcode-detector.txt` |
| [zxing-wasm](https://github.com/Sec-ant/zxing-wasm) 3.1.6: [zxing-cpp](https://github.com/zxing-cpp/zxing-cpp) compiled to WebAssembly, which reads the bookshelf's barcodes | `vendor/assets/wasm/zxing_reader.wasm`, and inside `barcode-detector--zxing-exported.js` | zxing-wasm MIT, © Ze-Zheng Wu (`licenses/zxing-wasm.txt`); zxing-cpp Apache License 2.0, © the zxing-cpp and ZXing authors (`licenses/zxing-cpp.txt`) |

## Used by the tests

| What | Where | License |
|---|---|---|
| [axe-core](https://github.com/dequelabs/axe-core) 4.14.0: the accessibility checks the system tests run in the browser | `test/vendor/axe.min.js` (its notice is at the top of the file) | Mozilla Public License 2.0, © Deque Systems, Inc. |
| Entries from [Wiktionary](https://www.wiktionary.org), as extracted by [kaikki.org](https://kaikki.org), shortened to the fields the importer reads (and, in one file, with malformed lines added on purpose) | `test/fixtures/files/lexicon/*.jsonl.gz` | CC BY-SA 4.0 (and the GFDL), by Wiktionary's contributors |

## The project's own documents

| What | Where | License |
|---|---|---|
| [Contributor Covenant](https://www.contributor-covenant.org) 2.1, with this project's way to report | `CODE_OF_CONDUCT.md` | CC BY 4.0, by the Organization for Ethical Source |

## Fetched by the app at run time

The assistant's dictionaries are Wiktionary's nouns, one language at a time, from kaikki.org's extracts (`config/lexicons.yml`, the admin's lexicon page). They are downloaded and imported by whoever runs the app, never committed. The data is CC BY-SA 4.0 (and GFDL), by Wiktionary's contributors. The lexicon page credits it ("Words from Wiktionary, via kaikki.org").

The bookshelf's lookups read [Open Library](https://openlibrary.org) and, when the admin saves a key, the Google Books API, each under its own terms. A book's page credits Open Library where its data came from there.
