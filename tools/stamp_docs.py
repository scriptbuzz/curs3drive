# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.
"""Update the draft marking and last-modified line in documents.

Usage (macOS or Windows):
    python tools/stamp_docs.py README.md other-doc.md
    python tools/stamp_docs.py --by mbitar README.md

The script replaces the first stamp line in each file with:
    _DRAFT - For internal use only. Last modified: YYYY-MM-DD HH:MM TZ by NAME._
It also recognizes the older form that starts with "_Last modified:".
"""

import argparse
import re
import sys
import time
from datetime import datetime
from pathlib import Path

AUTHOR = "mbitar"
MARKING = "DRAFT - For internal use only."
STAMP = re.compile(r"^_(?:DRAFT - For internal use only\. )?Last modified: .*_$", re.MULTILINE)


def stamp_line(author: str = AUTHOR) -> str:
    now = datetime.now().strftime("%Y-%m-%d %H:%M ") + time.strftime("%Z")
    return f"_{MARKING} Last modified: {now} by {author}._"


def stamp(path: Path, author: str = AUTHOR) -> bool:
    text = path.read_text(encoding="utf-8")
    updated, count = STAMP.subn(stamp_line(author), text, count=1)
    if count:
        path.write_text(updated, encoding="utf-8")
    return bool(count)


def main() -> int:
    parser = argparse.ArgumentParser(description="Update the stamp line in documents.")
    parser.add_argument("--by", default=AUTHOR, help="Name of the person who made the change.")
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()
    missing = [name for name in args.files if not stamp(Path(name), args.by)]
    for name in missing:
        print(f"{name} has no stamp line to update.", file=sys.stderr)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
