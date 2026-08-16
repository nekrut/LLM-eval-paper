# Build writeup.pdf from writeup.md via pandoc + pdflatex.
# The mermaid block in Methods is pre-rendered to figures/fig1_workflow_dag.png
# (see render-dag target below); the build swaps the ```mermaid block for an
# image embed at PDF time, leaving writeup.md unchanged for GitHub rendering.
#
# Requirements: pandoc, pdflatex (texlive-latex-recommended +
# texlive-latex-extra for newunicodechar), Python 3, npx (for render-dag).

PDF       := writeup.pdf
SRC       := writeup.md
TMP       := writeup.pandoc.md
HEADER    := writeup.header.tex
FIGS_DIR  := ../figures
DAG_PNG   := $(FIGS_DIR)/fig1_workflow_dag.png

PDF_GR    := writeup_GR.pdf
SRC_GR    := writeup_GR.md
TMP_GR    := writeup_GR.pandoc.md

.PHONY: all clean render-dag gr cover-letter supp-gr

cover-letter: cover_letter_GR.pdf

cover_letter_GR.pdf: cover_letter_GR.md
	pandoc cover_letter_GR.md -o $@ \
	    --pdf-engine=pdflatex \
	    -V colorlinks=true

supp-gr: supplement_GR.pdf

supplement_GR.pdf: supplement_GR.md $(HEADER)
	pandoc supplement_GR.md -o $@ \
	    --pdf-engine=pdflatex \
	    --resource-path=.:..:$(FIGS_DIR) \
	    -V geometry:margin=1in \
	    -V fontsize=10pt \
	    -V colorlinks=true \
	    -V documentclass=article \
	    -H $(HEADER)

all: $(PDF)

gr: $(PDF_GR)

$(PDF_GR): $(SRC_GR) $(HEADER)
	@python3 -c "import re; \
src = open('$(SRC_GR)').read(); \
m = re.search(r'\*\*Figure \d+\.\*\* ([^\n]+)\n+\`\`\`mermaid\n.*?\n\`\`\`', src, flags=re.DOTALL); \
out = re.sub(r'\*\*Figure \d+\.\*\* [^\n]+\n+\`\`\`mermaid\n.*?\n\`\`\`', '![' + (m.group(1) if m else '') + ']($(FIGS_DIR)/fig1_workflow_dag.png)', src, count=1, flags=re.DOTALL) if m else re.sub(r'\`\`\`mermaid\n.*?\n\`\`\`', '![]($(FIGS_DIR)/fig1_workflow_dag.png)', src, count=1, flags=re.DOTALL); \
open('$(TMP_GR)','w').write(out)"
	pandoc $(TMP_GR) -o $@ \
	    --pdf-engine=pdflatex \
	    --resource-path=.:..:$(FIGS_DIR) \
	    -V geometry:margin=1in \
	    -V fontsize=10pt \
	    -V colorlinks=true \
	    -V documentclass=article \
	    --lua-filter=tablewidths.lua \
	    --lua-filter=tablecaptions.lua \
	    -H $(HEADER)
	@rm -f $(TMP_GR)


$(PDF): $(SRC) $(HEADER)
	@python3 -c "import re; \
src = open('$(SRC)').read(); \
m = re.search(r'\*\*Figure \d+\.\*\* ([^\n]+)\n+\`\`\`mermaid\n.*?\n\`\`\`', src, flags=re.DOTALL); \
out = re.sub(r'\*\*Figure \d+\.\*\* [^\n]+\n+\`\`\`mermaid\n.*?\n\`\`\`', '![' + (m.group(1) if m else '') + ']($(FIGS_DIR)/fig1_workflow_dag.png)', src, count=1, flags=re.DOTALL) if m else re.sub(r'\`\`\`mermaid\n.*?\n\`\`\`', '![]($(FIGS_DIR)/fig1_workflow_dag.png)', src, count=1, flags=re.DOTALL); \
open('$(TMP)','w').write(out)"
	pandoc $(TMP) -o $@ \
	    --pdf-engine=pdflatex \
	    --resource-path=.:..:$(FIGS_DIR) \
	    -V geometry:margin=1in \
	    -V fontsize=10pt \
	    -V colorlinks=true \
	    -V documentclass=article \
	    --lua-filter=tablewidths.lua \
	    --lua-filter=tablecaptions.lua \
	    -H $(HEADER)
	@rm -f $(TMP)

# writeup.header.tex is a versioned file (not auto-generated). It carries
# the newunicodechar declarations for math/Greek glyphs and the fvextra
# Highlighting redefinition that wraps long lines in fenced code blocks.

# Re-render the workflow DAG from its mermaid source (block in writeup.md).
# Uses npx to fetch mermaid-cli on the fly; needs network on first run.
render-dag:
	@python3 -c "import re; \
src = open('$(SRC)').read(); \
m = re.search(r'\`\`\`mermaid\n(.*?)\n\`\`\`', src, flags=re.DOTALL); \
open('$(TMP).mmd','w').write(m.group(1))"
	@printf '{\n  \"args\": [\"--no-sandbox\", \"--disable-setuid-sandbox\"]\n}\n' > puppeteer-cfg.json
	npx --yes @mermaid-js/mermaid-cli@latest \
	    -i $(TMP).mmd -o $(DAG_PNG) -b white -w 1600 \
	    -p puppeteer-cfg.json
	@rm -f $(TMP).mmd puppeteer-cfg.json

clean:
	rm -f $(PDF) $(TMP)
