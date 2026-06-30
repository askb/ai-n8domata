#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Post-process a Mermaid-rendered SVG for committing.

  * strip Mermaid's base64 `data-points` layout metadata (smaller files, no
    secret-scanner false positives);
  * inject a theme-aware background so the file never shows GitHub's
    transparency checkerboard when opened directly, yet stays transparent
    when embedded inline in a README (where GitHub strips the <style>).

The background rect defaults to ``fill="none"`` (transparent). A <style>
block paints it white, or #0d1117 under ``prefers-color-scheme: dark`` — CSS
overrides the presentation attribute when the styles are honoured (raw/blob/
img view), and is simply ignored (transparent) when they are stripped inline.

Usage: postprocess.py FILE.svg [FILE.svg ...]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

BG_STYLE = (
    "<style>"
    ".diagram-bg{fill:#ffffff}"
    "@media (prefers-color-scheme:dark){.diagram-bg{fill:#0d1117}}"
    "</style>"
)


def process(path: Path) -> None:
    svg = path.read_text()
    svg = re.sub(r'\s+data-points="[^"]*"', "", svg)

    if 'class="diagram-bg"' not in svg:
        m = re.search(r"<svg\b[^>]*\bviewBox=\"([^\"]+)\"[^>]*>", svg)
        if not m:
            print(f"  {path.name}: no viewBox, skipping bg")
        else:
            x, y, w, h = (float(v) for v in m.group(1).split())
            rect = (
                f'<rect class="diagram-bg" x="{x:.2f}" y="{y:.2f}" '
                f'width="{w:.2f}" height="{h:.2f}" fill="none"/>'
            )
            svg = svg.replace(m.group(0), m.group(0) + BG_STYLE + rect, 1)

    path.write_text(svg)
    print(f"  post-processed {path.name}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: postprocess.py FILE.svg ...")
    for arg in sys.argv[1:]:
        process(Path(arg))
