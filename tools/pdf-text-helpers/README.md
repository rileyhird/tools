# PDF text helpers

Small Python scripts for working with text pulled from PDFs (`pdftotext` output, pages split on form feeds).

- `show.py FILE.txt PAGE [PAGE...]` prints the given PDF pages without blank lines.
- `pg.py FILE.txt REGEX` prints every line matching the regex (case-insensitive) with its page number.
