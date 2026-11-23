# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.
"""Write a small Excel workbook with made-up Cost and Usage Report rows.

The workbook is for demos and tests only. Account IDs, services and costs are
invented, so it is safe to copy anywhere. It needs only the Python standard
library, so it runs the same on macOS, Windows and Linux.

Usage:
    python tools/make_sample_workbook.py demo.xlsx
    python tools/make_sample_workbook.py demo.xlsx --rows 20000 --edition 2

The same rows and edition always produce the same cell values. A different
edition changes the costs, which makes the file look like an edited workbook.
"""

from __future__ import annotations

import argparse
import random
import sys
import zipfile
from datetime import date, timedelta
from pathlib import Path
from xml.sax.saxutils import escape

HEADERS = [
    "line_item_usage_account_id",
    "product_servicecode",
    "line_item_usage_type",
    "line_item_usage_start_date",
    "line_item_usage_amount",
    "line_item_unblended_cost",
]
ACCOUNTS = ["111122223333", "444455556666", "777788889999"]
SERVICES = [
    ("AmazonEC2", "BoxUsage:m5.xlarge"),
    ("AmazonS3", "TimedStorage-ByteHrs"),
    ("AWSStorageGateway", "UploadBytes"),
    ("AmazonVPC", "ClientVPN-EndpointHours"),
    ("AmazonCloudWatch", "CW:MetricMonitorUsage"),
]

CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>"""

ROOT_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>"""

WORKBOOK = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="CUR sample" sheetId="1" r:id="rId1"/></sheets>
</workbook>"""

WORKBOOK_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>"""


def column(index: int) -> str:
    """Return the Excel column letters for a zero-based column index."""
    letters = ""
    index += 1
    while index:
        index, rest = divmod(index - 1, 26)
        letters = chr(65 + rest) + letters
    return letters


def rows(count: int, edition: int):
    rng = random.Random(f"{count}-{edition}")
    start = date(2026, 10, 1)
    for _ in range(count):
        service, usage = rng.choice(SERVICES)
        amount = round(rng.uniform(0.1, 50), 4)
        yield [
            rng.choice(ACCOUNTS),
            service,
            usage,
            (start + timedelta(days=rng.randrange(31))).isoformat(),
            amount,
            round(amount * rng.uniform(0.01, 0.4), 6),
        ]


def cell(ref: str, value) -> str:
    if isinstance(value, (int, float)):
        return f'<c r="{ref}"><v>{value}</v></c>'
    return f'<c r="{ref}" t="inlineStr"><is><t>{escape(str(value))}</t></is></c>'


def sheet_xml(count: int, edition: int) -> str:
    lines = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
             '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>']
    for r, values in enumerate([HEADERS, *rows(count, edition)], start=1):
        cells = "".join(cell(f"{column(c)}{r}", v) for c, v in enumerate(values))
        lines.append(f'<row r="{r}">{cells}</row>')
    lines.append("</sheetData></worksheet>")
    return "\n".join(lines)


def write_workbook(path: Path, count: int = 5000, edition: int = 1) -> None:
    # A fixed timestamp keeps the file identical for the same rows and edition.
    stamp = (2026, 1, 1, 0, 0, 0)
    parts = {
        "[Content_Types].xml": CONTENT_TYPES,
        "_rels/.rels": ROOT_RELS,
        "xl/workbook.xml": WORKBOOK,
        "xl/_rels/workbook.xml.rels": WORKBOOK_RELS,
        "xl/worksheets/sheet1.xml": sheet_xml(count, edition),
    }
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, text in parts.items():
            archive.writestr(zipfile.ZipInfo(name, date_time=stamp), text)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Write an Excel workbook with made-up CUR rows.")
    parser.add_argument("path", type=Path, help="where to write the .xlsx file")
    parser.add_argument("--rows", type=int, default=5000, help="number of data rows, 5000 by default")
    parser.add_argument("--edition", type=int, default=1, help="changes the costs, to simulate an edited file")
    args = parser.parse_args(argv)
    write_workbook(args.path, args.rows, args.edition)
    print(f"Wrote {args.rows:,} rows to {args.path.name} ({args.path.stat().st_size:,} bytes).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
