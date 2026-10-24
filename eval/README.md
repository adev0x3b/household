# Evaluation data

What the app is measured against, kept apart from the test suite because
the app itself reads it: the eval dashboard lists and writes the scenarios,
and the OCR bench reads its cases.

- `assistant/scenarios/`: the assistant's scenarios, one YAML file each,
  played by `bin/rails assistant:eval` and the evals pages
  (`lib/assistant_eval/`; docs/architecture/assistant.md, "Measuring it").
- `lab_reports/ocr/`: the lab report OCR bench's cases, drawn from their
  rows or read from a real screenshot beside them, scored by
  `bin/rails lab_reports:ocr_bench` (`lib/lab_reports/ocr_bench.rb`).
