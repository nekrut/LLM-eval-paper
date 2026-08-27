#!/usr/bin/env python3
"""Markdown -> PDF via python-markdown + headless Chromium.

This box has no pandoc or LaTeX, so the PDF build renders the markdown to
HTML with a print stylesheet and prints it with Chromium. Figures are
resolved relative to the source file. The <!-- addresses: --> comments are
stripped; they are working annotations, not manuscript content.

Usage: python3 md2pdf.py input.md output.pdf
"""
import re, subprocess, sys, pathlib, tempfile
import markdown

CSS = """
@page { size: letter; margin: 25mm 22mm; }
body { font-family: "DejaVu Serif", Georgia, serif; font-size: 10.5pt;
       line-height: 1.45; color: #111; max-width: 100%; }
h1 { font-size: 16pt; line-height: 1.3; margin-top: 0; }
h2 { font-size: 13pt; border-bottom: 1px solid #999; padding-bottom: 2px;
     margin-top: 1.6em; }
h3 { font-size: 11.5pt; margin-top: 1.3em; }
h4 { font-size: 10.5pt; }
code { font-family: "DejaVu Sans Mono", monospace; font-size: 8.8pt;
       background: #f4f4f4; padding: 0 2px; }
pre { background: #f4f4f4; padding: 6px 8px; font-size: 8.3pt;
      white-space: pre-wrap; word-wrap: break-word; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; margin: 0.8em 0; font-size: 8.8pt;
        width: 100%; page-break-inside: avoid; }
th, td { border: 1px solid #bbb; padding: 3px 6px; text-align: left;
         vertical-align: top; }
th { background: #eee; }
img { max-width: 100%; page-break-inside: avoid; }
blockquote { border-left: 3px solid #ccc; margin-left: 0; padding-left: 12px;
             color: #444; }
h1, h2, h3, h4 { page-break-after: avoid; }
"""

def main(src, dst):
    src = pathlib.Path(src).resolve()
    text = src.read_text()
    text = re.sub(r"<!--\s*addresses:.*?-->", "", text, flags=re.S)
    body = markdown.markdown(text, extensions=["tables", "fenced_code"])
    html = (f"<!doctype html><html><head><meta charset='utf-8'>"
            f"<style>{CSS}</style></head><body>{body}</body></html>")
    with tempfile.NamedTemporaryFile("w", suffix=".html", dir=src.parent,
                                     delete=False) as f:
        f.write(html); tmp = pathlib.Path(f.name)
    try:
        r = subprocess.run(
            ["chromium", "--headless", "--disable-gpu", "--no-sandbox",
             f"--print-to-pdf={pathlib.Path(dst).resolve()}",
             "--no-pdf-header-footer", f"file://{tmp}"],
            capture_output=True, text=True, timeout=180)
        if r.returncode != 0:
            print(r.stderr[-500:], file=sys.stderr); return 1
    finally:
        tmp.unlink()
    print(f"wrote {dst}")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
