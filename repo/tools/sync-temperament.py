#!/usr/bin/env python3
"""Copies src/temperament.js into both pieces, between the TEMPERAMENT markers.

The two HTML files stay self-contained, so the block has to live inside each.
This keeps one source for it. Edit src/temperament.js, then run:

    python3 tools/sync-temperament.py          write the block into both pieces
    python3 tools/sync-temperament.py --check  report drift, change nothing
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BEGIN, END = "<!-- TEMPERAMENT:BEGIN -->", "<!-- TEMPERAMENT:END -->"
PIECES = ["i-see-you.html", "oculus.html"]


def main():
    check = "--check" in sys.argv[1:]
    source = (ROOT / "src" / "temperament.js").read_text(encoding="utf-8")
    block = BEGIN + "\n<script>\n" + source + "</script>\n" + END
    drift = False
    for name in PIECES:
        path = ROOT / name
        html = path.read_text(encoding="utf-8")
        if html.count(BEGIN) != 1 or html.count(END) != 1:
            print(f"{name}: markers missing or repeated, left alone")
            drift = True
            continue
        start, end = html.index(BEGIN), html.index(END) + len(END)
        updated = html[:start] + block + html[end:]
        if updated == html:
            print(f"{name}: in sync")
        elif check:
            print(f"{name}: differs from src/temperament.js")
            drift = True
        else:
            path.write_text(updated, encoding="utf-8")
            print(f"{name}: updated")
    return 1 if drift else 0


if __name__ == "__main__":
    sys.exit(main())
