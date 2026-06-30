#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Turn a static Mermaid SVG into an animated, interactive diagram.

Reads architecture.svg (rendered by render.sh) and emits:
  * architecture.animated.svg  — flowing data particles along every edge,
    marching-ant links and hover highlight (pure SMIL/CSS, no JS). Animates
    in any browser when opened directly (raw GitHub, local, GitHub Pages).
  * architecture.html          — the animated SVG in a self-contained page
    with a legend, zoom/pan and per-service tooltips.

GitHub strips animation from SVGs embedded *inline* in a README, so the
static architecture.svg is what shows there; these two files are the "live"
view linked from the docs.
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

HERE = Path(__file__).parent
SRC = HERE / "architecture.svg"

# node key -> human description (tooltip)
DESC = {
    "CF": "Cloudflare Tunnel — secure public ingress (no open ports)",
    "TR": "Traefik — reverse proxy, TLS termination & routing",
    "N8N": "n8n Main — workflow orchestrator & editor UI",
    "NW": "n8n Workers — queue job executors (auto-scaled)",
    "NH": "n8n Webhooks — inbound webhook handler",
    "PG": "PostgreSQL — n8n + application database",
    "RD": "Redis — Bull queue & cache",
    "MC": "MinIO — S3-compatible object storage for media",
    "BR": "Baserow — no-code database / content backend",
    "TTS": "Kokoro TTS — text-to-speech narration",
    "NCA": "NCA Toolkit — FFmpeg media API (+ yt-dlp)",
    "CRP": "Intelligent Cropper — smart subject/face cropping",
    "SVM": "Short Video Maker — automated short-form builder",
    "AVA": "SadTalker — talking-head avatar generation",
    "ACE": "ACE-Step — music generation (GPU)",
    "AIA": "AI Agents — no-code AI agent tooling",
    "QM": "Queue Metrics — Redis queue-depth monitor",
    "DS": "Dynamic Scaler — autoscales n8n workers on load",
    "BK": "Backup — scheduled database & n8n backups",
    "MCP": "MCP Server — n8n Model Context Protocol tools",
}

STYLE = """
<style>
  .flowchart-link{stroke-dasharray:9 7;animation:flowdash 1s linear infinite;}
  @keyframes flowdash{to{stroke-dashoffset:-32;}}
  .flow-dot{fill:#ffd23f;filter:drop-shadow(0 0 4px #ffd23f);}
  .node{cursor:pointer;transition:filter .15s ease;}
  .node:hover{filter:brightness(1.18) drop-shadow(0 0 6px rgba(0,0,0,.35));}
  .node rect,.node path,.node circle,.node polygon{transition:filter .15s ease;}
  @media (prefers-reduced-motion: reduce){
    .flowchart-link{animation:none;}
    .flow-dot{display:none;}
  }
</style>
"""


def edge_ids(svg: str):
    """Return [full_id, ...] for every flowchart-link path."""
    out = []
    id_first = re.compile(
        r'<path\b[^>]*\bid="([^"]+)"[^>]*\bclass="[^"]*flowchart-link[^"]*"'
    )
    class_first = re.compile(
        r'<path\b[^>]*\bclass="[^"]*flowchart-link[^"]*"[^>]*\bid="([^"]+)"'
    )
    for m in id_first.finditer(svg):
        out.append(m.group(1))
    for m in class_first.finditer(svg):
        if m.group(1) not in out:
            out.append(m.group(1))
    return out


def make_dots(ids):
    dots = ['<g class="flow-layer" aria-hidden="true">']
    for i, pid in enumerate(ids):
        dur = 2.0 + (i % 5) * 0.35          # 2.0–3.4s, varied = organic
        begin = -(i % 7) * 0.4              # stagger starts
        dots.append(
            f'<circle class="flow-dot" r="6">'
            f'<animateMotion dur="{dur:.2f}s" begin="{begin:.2f}s" '
            f'repeatCount="indefinite" rotate="auto" calcMode="linear" '
            f'keyPoints="0;1" keyTimes="0;1">'
            f'<mpath xlink:href="#{pid}" href="#{pid}"/>'
            f"</animateMotion></circle>"
        )
    dots.append("</g>")
    return "\n".join(dots)


def add_tooltips(svg: str) -> str:
    def esc(s):
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    def repl(m):
        head, key = m.group(0), m.group(1)
        d = DESC.get(key)
        if not d:
            return head
        # insert a <title> right after the opening <g ...> of the node
        return head + f"<title>{esc(d)}</title>"
    return re.sub(r'<g class="node[^"]*" id="[^"]*flowchart-([A-Z0-9]+)-\d+"[^>]*>', repl, svg)


def build():
    if not SRC.exists():
        sys.exit(f"missing {SRC} — run render.sh first")
    svg = SRC.read_text()
    svg = re.sub(r'\s+data-points="[^"]*"', "", svg)  # drop base64 layout metadata
    ids = edge_ids(svg)
    if not ids:
        sys.exit("no flowchart-link edges found")

    svg = add_tooltips(svg)
    # ensure xlink namespace for <mpath xlink:href>
    if "xmlns:xlink" not in svg:
        svg = svg.replace("<svg ", '<svg xmlns:xlink="http://www.w3.org/1999/xlink" ', 1)
    # inject <style> right after the opening <svg ...> tag
    svg = re.sub(r"(<svg\b[^>]*>)", r"\1" + STYLE, svg, count=1)
    # inject the flow dots just before </svg>
    svg = svg.replace("</svg>", make_dots(ids) + "\n</svg>")

    (HERE / "architecture.animated.svg").write_text(svg)
    print(f"wrote architecture.animated.svg ({len(ids)} animated edges)")

    template = (HERE / "_viewer.html").read_text()
    (HERE / "architecture.html").write_text(template.replace("__SVG__", svg))
    print("wrote architecture.html")


if __name__ == "__main__":
    build()
