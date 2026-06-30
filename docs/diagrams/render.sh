#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
##############################################################################
# Render every Mermaid source (docs/diagrams/*.mmd) to a themed SVG.
#
# Diagrams are committed as SVG so they render intuitively (color-coded
# layers, icons, DB shapes) on GitHub and anywhere else, without relying on
# Mermaid live-rendering. Edit the .mmd source, then re-run this script.
#
# Requires: @mermaid-js/mermaid-cli (mmdc) + a Chrome/Chromium.
#   npm install -g @mermaid-js/mermaid-cli   # or run via npx
#   export CHROME=/usr/bin/google-chrome     # path to your browser
##############################################################################
set -euo pipefail
cd "$(dirname "$0")"

CHROME="${CHROME:-/usr/bin/google-chrome}"
MMDC="${MMDC:-mmdc}"
command -v "$MMDC" >/dev/null 2>&1 || MMDC="npx -y @mermaid-js/mermaid-cli"

PPTR="$(mktemp)"
trap 'rm -f "$PPTR"' EXIT
cat >"$PPTR" <<JSON
{"executablePath":"${CHROME}","args":["--no-sandbox","--disable-gpu"]}
JSON

for src in *.mmd; do
    [ -e "$src" ] || continue
    out="${src%.mmd}.svg"
    echo "rendering ${src} -> ${out}"
    $MMDC -i "$src" -o "$out" -c mermaid-config.json -p "$PPTR" -b transparent
    # drop Mermaid's base64 layout metadata (not needed to render; trips secret scanners)
    sed -i 's/ data-points="[^"]*"//g' "$out"
done

# Build the animated SVG + interactive HTML from architecture.svg.
if [ -f make_interactive.py ]; then
    echo "building animated + interactive views"
    python3 make_interactive.py
fi
echo "done."
