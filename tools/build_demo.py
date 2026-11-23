# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.
"""Turn the demo recording into an animated terminal view and a transcript page.

scripts/demo.sh writes docs/demo/recording.log while it runs. This script reads
that recording and writes:
- docs/demo/demo.svg: an animated terminal window that shows one step at a time
  and loops. GitHub plays the animation inside the README.
- docs/demo.md: the full transcript, with the measured results of every step.

With Google Chrome installed, it also checks that no text in any slide runs
outside the terminal window or overlaps other text.

Usage:
    python tools/build_demo.py
"""

from __future__ import annotations

import html
import json
import re
import sys
import tempfile
import textwrap
from pathlib import Path
from xml.sax.saxutils import escape

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_diagrams import chrome, find_chrome  # noqa: E402
from stamp_docs import stamp_line  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
RECORDING = ROOT / "docs" / "demo" / "recording.log"
SVG_OUT = ROOT / "docs" / "demo" / "demo.svg"
PAGE_OUT = ROOT / "docs" / "demo.md"

WIDTH, HEIGHT = 1000, 600
LEFT, RIGHT = 32, 968
SLIDE_SECONDS = 6
MONO_CHARS = 112  # characters per line at 13 px in the monospace font
LINE = 18
BODY_BOTTOM = 548


def parse(path: Path) -> dict:
    meta, steps, done = {}, [], {}
    lines = path.read_text(encoding="utf-8").splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("@@META "):
            key, _, value = line[7:].partition("=")
            meta[key] = value
        elif line.startswith("@@STEP "):
            number, _, caption = line[7:].partition("|")
            steps.append({"number": int(number), "caption": caption, "commands": []})
        elif line.startswith("@@CMD "):
            command = {"command": line[6:], "output": [], "status": None, "seconds": None}
            i += 2  # skip the @@OUT marker
            while i < len(lines) and not lines[i].startswith("@@END "):
                command["output"].append(lines[i])
                i += 1
            if i < len(lines):
                status, seconds = lines[i][6:].split()
                command["status"], command["seconds"] = int(status), float(seconds)
            while command["output"] and not command["output"][-1].strip():
                command["output"].pop()
            steps[-1]["commands"].append(command)
        elif line.startswith("@@DONE "):
            done = dict(part.split("=") for part in line[7:].split())
        i += 1
    return {"meta": meta, "steps": steps, "done": done}


def find_number(steps: list[dict], pattern: str) -> list[str]:
    found = []
    for step in steps:
        for command in step["commands"]:
            for line in command["output"]:
                match = re.search(pattern, line)
                if match:
                    found.append(match.group(1))
    return found


def duration(seconds: str) -> str:
    value = float(seconds)
    if value < 1:
        return "in less than a second"
    if value == 1:
        return "after 1 second"
    return f"after {value:.1f} seconds".replace(".0 seconds", " seconds")


def highlights(recording: dict) -> list[str]:
    steps = recording["steps"]
    copies = find_number(steps, r"The copy took ([\d.]+) seconds")
    uploads = find_number(steps, r"new version of the file (\d+) seconds? after the save finished")
    appeared = find_number(steps, r"appeared on the share (\d+) seconds?")
    checksum = any("The checksums match." in line for s in steps for c in s["commands"] for line in c["output"])
    encryption = find_number(steps, r"SMB_CURR_ENCRYPT_ALGORITHM\s+(\S+)")
    version = find_number(steps, r"SMB_VERSION\s+(\S+)")
    points = []
    if version and encryption:
        points.append(f"The share used {version[0].replace('_', ' ')} with {encryption[0]} encryption.")
    if copies:
        points.append(f"Copying the 6.5 MB workbook to the share took {float(copies[0]):.1f} seconds.")
    if uploads:
        points.append(f"The new file was in S3 {duration(uploads[0])}, counted from the end of the copy.")
    if checksum:
        points.append("The file downloaded from S3 matched the original byte for byte.")
    if len(uploads) > 1:
        points.append(f"The edited version reached S3 {duration(uploads[1])}, and S3 kept the old version.")
    if appeared:
        wait = float(appeared[0])
        delay = "less than a second" if wait < 1 else "1 second" if wait == 1 else f"{wait:g} seconds"
        points.append(f"A file written straight to S3 appeared on the share {delay} after a refresh.")
    return points


# ---------- Animated SVG ----------

def text(x, y, content, cls, anchor="start"):
    return (f'<text x="{x}" y="{y}" class="{cls}" text-anchor="{anchor}" xml:space="preserve">'
            f"{escape(content)}</text>")


def wrap_command(command: str) -> list[str]:
    parts = textwrap.wrap("$ " + command, MONO_CHARS, subsequent_indent="    ",
                          break_long_words=True, break_on_hyphens=False)
    return parts or ["$"]


def clip(line: str) -> str:
    line = line.replace("\t", "    ")
    return line if len(line) <= MONO_CHARS else line[: MONO_CHARS - 1] + "…"


def slide_body(step: dict, top: int) -> list[str]:
    out, y = [], top
    rows = []
    for command in step["commands"]:
        rows += [(line, "cmd") for line in wrap_command(command["command"])]
        rows += [(clip(line), "out") for line in command["output"]]
        if command["status"]:
            rows.append((f"The command failed with exit code {command['status']}.", "fail"))
        rows.append(("", "gap"))
    limit = (BODY_BOTTOM - top) // LINE
    if len(rows) > limit:
        hidden = len(rows) - limit + 1
        rows = rows[: limit - 1] + [(f"{hidden} more lines are in the full transcript.", "dim")]
    for content, cls in rows:
        if cls != "gap":
            out.append(text(LEFT, y, content, cls))
        y += LINE
    return out


def caption_lines(caption: str) -> list[str]:
    return textwrap.wrap(caption, 82)


def build_svg(recording: dict) -> str:
    meta, steps, done = recording["meta"], recording["steps"], recording["done"]
    total = len(steps)
    slides = []

    title = [
        text(WIDTH // 2, 150, "Excel files in Amazon S3, opened as a network drive", "big", "middle"),
        text(WIDTH // 2, 186, f"Live demo recorded on {meta.get('started', '')} on a Mac connected through AWS Client VPN.", "sub", "middle"),
        text(WIDTH // 2, 212, f"Gateway {meta.get('gateway', '')} at {meta.get('address', '')}, bucket {meta.get('bucket', '')}, Region {meta.get('region', '')}.", "sub", "middle"),
    ]
    title += [
        text(WIDTH // 2, 300, f"The demo runs {total} steps, one per slide.", "list", "middle"),
        text(WIDTH // 2, 328, "Each slide shows the real commands and their real output.", "list", "middle"),
        text(WIDTH // 2, 356, "The workbook holds made-up CUR data, so it is safe to show.", "list", "middle"),
    ]
    slides.append(title)

    for step in steps:
        body = [text(LEFT, 76, f"STEP {step['number']} OF {total}", "kicker")]
        cy = 104
        for line in caption_lines(step["caption"]):
            body.append(text(LEFT, cy, line, "caption"))
            cy += 24
        body += slide_body(step, cy + 14)
        slides.append(body)

    failures = int(done.get("failures", "0"))
    seconds = done.get("seconds", "?")
    summary = [
        text(WIDTH // 2, 150, "Every step succeeded." if failures == 0 else f"{failures} commands failed.",
             "big ok" if failures == 0 else "big fail", "middle"),
        text(WIDTH // 2, 186, f"The whole demo took {seconds} seconds.", "sub", "middle"),
    ]
    y = 250
    for point in highlights(recording):
        summary.append(text(140, y, "✓  " + point, "list"))
        y += 30
    slides.append(summary)

    cycle = len(slides) * SLIDE_SECONDS
    share = 100 / len(slides)
    fade = min(share * 0.08, 1.5)
    styles, groups = [], []
    for i, body in enumerate(slides):
        start, end = i * share, (i + 1) * share
        frames = [f"0% {{ opacity: {1 if i == 0 else 0}; }}"]
        if i > 0:
            frames.append(f"{max(start - 0.001, 0):.3f}% {{ opacity: 0; }}")
            frames.append(f"{start + fade:.3f}% {{ opacity: 1; }}")
        frames.append(f"{max(end - fade, start + fade):.3f}% {{ opacity: 1; }}")
        frames.append(f"{min(end, 100):.3f}% {{ opacity: 0; }}")
        frames.append("100% { opacity: 0; }")
        styles.append(f"@keyframes s{i} {{ {' '.join(frames)} }}")
        styles.append(f".s{i} {{ opacity: {1 if i == 0 else 0}; animation: s{i} {cycle}s linear infinite; }}")
        groups.append(f'<g class="slide s{i}" data-slide="{i}">' + "".join(body) + "</g>")

    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {WIDTH} {HEIGHT}" width="{WIDTH}" height="{HEIGHT}">
<title>Live demo of the CUR file share, recorded {escape(meta.get('started', ''))}</title>
<style>
text {{ white-space: pre; }}
.big {{ font: 700 28px "Helvetica Neue", Helvetica, Arial, sans-serif; fill: #FFFFFF; }}
.ok {{ fill: #7EE787; }}
.fail {{ font: 13px "SF Mono", Menlo, Consolas, monospace; fill: #FF7B72; }}
.big.fail {{ font: 700 28px "Helvetica Neue", Helvetica, Arial, sans-serif; }}
.sub {{ font: 15px "Helvetica Neue", Helvetica, Arial, sans-serif; fill: #A9B1BD; }}
.list {{ font: 16px "Helvetica Neue", Helvetica, Arial, sans-serif; fill: #E6EDF3; }}
.kicker {{ font: 700 13px "Helvetica Neue", Helvetica, Arial, sans-serif; fill: #58A6FF; letter-spacing: 1px; }}
.caption {{ font: 700 19px "Helvetica Neue", Helvetica, Arial, sans-serif; fill: #FFFFFF; }}
.cmd {{ font: 13px "SF Mono", Menlo, Consolas, monospace; fill: #79C0FF; }}
.out {{ font: 13px "SF Mono", Menlo, Consolas, monospace; fill: #E6EDF3; }}
.dim {{ font: 13px "SF Mono", Menlo, Consolas, monospace; fill: #8B949E; }}
.bar {{ animation: bar {cycle}s linear infinite; }}
@keyframes bar {{ from {{ width: 0px; }} to {{ width: {RIGHT - LEFT}px; }} }}
{chr(10).join(styles)}
</style>
<rect width="{WIDTH}" height="{HEIGHT}" rx="12" fill="#0D1117"/>
<rect width="{WIDTH}" height="38" rx="12" fill="#161B22"/>
<rect y="26" width="{WIDTH}" height="12" fill="#161B22"/>
<circle cx="22" cy="19" r="6" fill="#FF5F57"/><circle cx="42" cy="19" r="6" fill="#FEBC2E"/><circle cx="62" cy="19" r="6" fill="#28C840"/>
<text x="{WIDTH // 2}" y="24" text-anchor="middle" style="font: 13px 'Helvetica Neue', Helvetica, Arial, sans-serif; fill: #8B949E;">Live demo of the CUR file share</text>
{chr(10).join(groups)}
<rect x="{LEFT}" y="574" width="{RIGHT - LEFT}" height="4" rx="2" fill="#21262D"/>
<rect class="bar" x="{LEFT}" y="574" width="0" height="4" rx="2" fill="#58A6FF"/>
</svg>
"""


# ---------- Layout check ----------

CHECK_SCRIPT = """
<script>
const svg = document.querySelector('svg');
const base = svg.getBoundingClientRect();
const problems = [];
document.querySelectorAll('.slide').forEach(g => {
  g.style.animation = 'none'; g.style.opacity = 1;
  const texts = [...g.querySelectorAll('text')].map(t => { const r = t.getBoundingClientRect();
    return {t: t.textContent, x: r.left - base.left, y: r.top - base.top, w: r.width, h: r.height}; });
  for (const a of texts) {
    if (a.x < 20 || a.x + a.w > %(width)d - 20 || a.y < 44 || a.y + a.h > 566)
      problems.push(`Slide ${g.dataset.slide}: text leaves the window: "${a.t.slice(0, 60)}"`);
  }
  for (let i = 0; i < texts.length; i++) for (let j = i + 1; j < texts.length; j++) {
    const a = texts[i], b = texts[j];
    if (a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h - 1 && b.y < a.y + a.h - 1)
      problems.push(`Slide ${g.dataset.slide}: "${a.t.slice(0, 40)}" overlaps "${b.t.slice(0, 40)}"`);
  }
  g.style.opacity = 0;
});
const out = document.createElement('pre'); out.id = 'result';
out.textContent = JSON.stringify(problems); document.body.appendChild(out);
</script>
"""


def check_layout(svg: str) -> list[str]:
    try:
        binary = find_chrome(None)
    except SystemExit:
        print("Google Chrome was not found, so the layout check was skipped.")
        return []
    with tempfile.TemporaryDirectory() as folder:
        page = Path(folder) / "check.html"
        page.write_text("<!doctype html><meta charset='utf-8'><body style='margin:0'>" + svg
                        + CHECK_SCRIPT % {"width": WIDTH} + "</body>", encoding="utf-8")
        dom = chrome(binary, f"--window-size={WIDTH},{HEIGHT}", "--virtual-time-budget=2000", "--dump-dom", page.as_uri())
    found = re.search(r'<pre id="result">(.*?)</pre>', dom, re.S)
    return json.loads(html.unescape(found.group(1))) if found else ["Chrome returned no layout results."]


# ---------- Transcript page ----------

def build_page(recording: dict) -> str:
    meta, steps, done = recording["meta"], recording["steps"], recording["done"]
    failures = int(done.get("failures", "0"))
    outcome = (f"Every step succeeded, and the whole demo took {done.get('seconds', '?')} seconds."
               if failures == 0 else f"{failures} commands failed. The transcript below shows which.")
    lines = [
        "# Live Demo",
        "",
        stamp_line(),
        "",
        "This page shows a real run of the proof of concept, recorded on a Mac connected through AWS Client VPN. "
        "The demo copies a workbook of made-up CUR data to the file share, follows it into S3, saves an edited "
        "version, and shows a file written straight to S3 appearing on the share. "
        f"It was recorded on {meta.get('started', '')}. {outcome}",
        "",
        "[Back to the README](../README.md)",
        "",
        "![Animated terminal window that plays the demo one step at a time.](demo/demo.svg)",
        "",
        "## What the demo proved",
        "",
    ]
    lines += [f"- {point}" for point in highlights(recording)]
    lines += ["", "## Steps", "", "| Step | What it shows | Result | Time |", "|---|---|---|---|"]
    for step in steps:
        ok = all(c["status"] == 0 for c in step["commands"])
        seconds = sum(c["seconds"] or 0 for c in step["commands"])
        lines.append(f"| {step['number']} | {step['caption']} | {'Succeeded' if ok else 'Failed'} | {seconds:.1f} s |")
    lines += ["", "## Full transcript", "",
              "Commands show shell variables such as `$BUCKET` instead of their values. "
              "The demo script sets them from the Terraform outputs.", ""]
    for step in steps:
        lines += [f"### Step {step['number']}", "", step["caption"], "", "```text"]
        for command in step["commands"]:
            lines.append("$ " + command["command"])
            lines += command["output"]
            lines.append("")
        if lines[-1] == "":
            lines.pop()
        lines += ["```", ""]
    lines += [
        "## Run the demo yourself",
        "",
        "1. Connect the AWS VPN Client and mount the share in Finder, as described in [Connect from macOS](connect-macos.md).",
        "2. Sign in to AWS with `aws sso login --profile sandbox01`.",
        "3. From the repository root, run the demo, then rebuild this page and the animation:",
        "",
        "```bash",
        "scripts/demo.sh",
        "```",
        "",
        "```bash",
        "python3 tools/build_demo.py",
        "```",
        "",
        "The demo runs in Terminal, because macOS lets Terminal use the network share once you allow it. "
        "It leaves its files in the `demo` folder of the share, so the bucket keeps a record of each run.",
        "",
        "---",
        "",
        "_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. "
        "See the [license](../LICENSE) and the [disclaimers](../DISCLAIMER.md)._",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    if not RECORDING.exists():
        sys.exit(f"No recording found at {RECORDING.relative_to(ROOT)}. Run scripts/demo.sh first.")
    recording = parse(RECORDING)
    svg = build_svg(recording)
    SVG_OUT.write_text(svg, encoding="utf-8")
    PAGE_OUT.write_text(build_page(recording), encoding="utf-8")
    problems = check_layout(svg)
    print(f"Wrote {SVG_OUT.relative_to(ROOT)} with {len(recording['steps']) + 2} slides "
          f"and {PAGE_OUT.relative_to(ROOT)}. Layout problems: {len(problems)}.")
    for problem in problems:
        print("  " + problem)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
