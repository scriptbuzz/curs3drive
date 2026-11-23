# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.
"""Build the architecture diagrams from their source files and check their layout.

For every docs/diagrams/src/<name>.svg the script:
1. Embeds each icon referenced as href="icons/<file>.svg" as a data URI, so the
   finished diagram is a single file that renders on GitHub and in any browser.
2. Writes the result to docs/diagrams/<name>.svg.
3. Renders docs/diagrams/<name>.png at twice the size with headless Google Chrome.
4. Measures every text element in Chrome and fails if any text runs off the
   canvas, leaves the box named in its data-in attribute, or overlaps other text,
   an icon or a numbered step marker.

Usage (macOS, Windows or Linux, with Google Chrome installed):
    python tools/build_diagrams.py
    python tools/build_diagrams.py --chrome "C:/Program Files/Google/Chrome/Application/chrome.exe"
"""

from __future__ import annotations

import argparse
import base64
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "docs" / "diagrams" / "src"
OUT = ROOT / "docs" / "diagrams"
ICON_HREF = re.compile(r'href="icons/([A-Za-z0-9._-]+\.svg)"')
VIEWBOX = re.compile(r'viewBox="0 0 (\d+) (\d+)"')
PADDING = 4  # minimum distance in pixels between text and the edge of its box

CHROME_CANDIDATES = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "google-chrome",
    "google-chrome-stable",
    "chromium",
    "chromium-browser",
]

MEASURE_SCRIPT = """
<script>
const svg = document.querySelector('svg');
const base = svg.getBoundingClientRect();
const box = el => { const r = el.getBoundingClientRect();
  return {x: r.left - base.left, y: r.top - base.top, w: r.width, h: r.height}; };
const overlap = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
const W = svg.viewBox.baseVal.width, H = svg.viewBox.baseVal.height, P = %(padding)d;
const problems = [];
const texts = [...svg.querySelectorAll('text')].map(el => ({el, b: box(el), t: el.textContent.trim()}));
const obstacles = [...svg.querySelectorAll('image, .marker')].map(el => ({b: box(el), t: el.getAttribute('href')?.slice(0, 30) || el.textContent.trim() || 'marker'}));
for (const {el, b, t} of texts) {
  if (b.x < 0 || b.y < 0 || b.x + b.w > W || b.y + b.h > H) problems.push(`Text runs off the canvas: "${t}"`);
  const inId = el.closest('[data-in]')?.getAttribute('data-in');
  if (inId) {
    const container = svg.getElementById(inId);
    if (!container) problems.push(`Text "${t}" names a missing box "${inId}"`);
    else { const c = box(container);
      if (b.x < c.x + P || b.y < c.y + P || b.x + b.w > c.x + c.w - P || b.y + b.h > c.y + c.h - P)
        problems.push(`Text leaves its box "${inId}": "${t}"`); }
  }
  if (el.closest('.marker')) continue;
  for (const o of obstacles) if (overlap(b, o.b)) problems.push(`Text "${t}" overlaps an icon or marker (${o.t})`);
}
for (let i = 0; i < texts.length; i++) for (let j = i + 1; j < texts.length; j++) {
  const a = texts[i], c = texts[j];
  if (a.el.closest('.marker') && a.el.closest('.marker') === c.el.closest('.marker')) continue;
  if (overlap(a.b, c.b)) problems.push(`Text "${a.t}" overlaps text "${c.t}"`);
}
const out = document.createElement('pre'); out.id = 'result';
out.textContent = JSON.stringify({texts: texts.length, icons: obstacles.length, problems});
document.body.appendChild(out);
</script>
"""


def find_chrome(explicit: str | None) -> str:
    for candidate in ([explicit] if explicit else []) + CHROME_CANDIDATES:
        if candidate and (Path(candidate).exists() or shutil.which(candidate)):
            return candidate
    sys.exit("Google Chrome was not found. Pass its path with --chrome.")


def embed_icons(svg: str) -> str:
    def to_data_uri(match: re.Match) -> str:
        icon = (SRC / "icons" / match.group(1)).read_bytes()
        return 'href="data:image/svg+xml;base64,' + base64.b64encode(icon).decode("ascii") + '"'

    return ICON_HREF.sub(to_data_uri, svg)


def chrome(binary: str, *args: str) -> str:
    with tempfile.TemporaryDirectory() as profile:
        result = subprocess.run(
            [binary, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
             f"--user-data-dir={profile}", *args],
            capture_output=True, text=True, timeout=120,
        )
    return result.stdout


def build(name: Path, binary: str) -> list[str]:
    source = name.read_text(encoding="utf-8")
    width, height = map(int, VIEWBOX.search(source).groups())
    finished = embed_icons(source)
    svg_path = OUT / name.name
    svg_path.write_text(finished, encoding="utf-8")

    png_path = svg_path.with_suffix(".png")
    chrome(binary, "--force-device-scale-factor=2", f"--window-size={width},{height}",
           f"--screenshot={png_path}", svg_path.as_uri())

    with tempfile.TemporaryDirectory() as folder:
        page = Path(folder) / "measure.html"
        page.write_text(
            "<!doctype html><html><head><meta charset='utf-8'><style>body{margin:0}</style></head><body>"
            + re.sub(r"^<\?xml[^>]*>\s*", "", finished)
            + MEASURE_SCRIPT % {"padding": PADDING}
            + "</body></html>",
            encoding="utf-8",
        )
        dom = chrome(binary, f"--window-size={width},{height}", "--virtual-time-budget=3000",
                     "--dump-dom", page.as_uri())

    found = re.search(r'<pre id="result">(.*?)</pre>', dom, re.S)
    if not found:
        return [f"{name.name}: Chrome returned no measurements."]
    report = json.loads(html.unescape(found.group(1)))
    print(f"{svg_path.relative_to(ROOT)}: {report['texts']} text elements, {report['icons']} icons and markers checked, "
          f"{len(report['problems'])} problems. PNG written to {png_path.relative_to(ROOT)}.")
    return [f"{name.name}: {p}" for p in report["problems"]]


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the diagrams and check their layout.")
    parser.add_argument("--chrome", help="path to the Google Chrome program")
    args = parser.parse_args()
    binary = find_chrome(args.chrome or os.environ.get("CHROME"))

    problems: list[str] = []
    for source in sorted(SRC.glob("*.svg")):
        problems += build(source, binary)

    for problem in problems:
        print("  " + problem)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
