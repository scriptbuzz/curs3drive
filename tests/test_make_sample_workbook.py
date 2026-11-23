# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

import make_sample_workbook as wb  # noqa: E402


class SampleWorkbookTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.path = Path(self.folder.name) / "sample.xlsx"

    def test_contains_required_parts(self):
        wb.write_workbook(self.path, 10)
        with zipfile.ZipFile(self.path) as archive:
            names = set(archive.namelist())
        self.assertTrue({"[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/worksheets/sheet1.xml"} <= names)

    def test_writes_header_plus_rows(self):
        wb.write_workbook(self.path, 25)
        with zipfile.ZipFile(self.path) as archive:
            sheet = archive.read("xl/worksheets/sheet1.xml").decode()
        self.assertEqual(sheet.count("<row "), 26)

    def test_same_settings_give_identical_files(self):
        other = Path(self.folder.name) / "other.xlsx"
        wb.write_workbook(self.path, 50, edition=1)
        wb.write_workbook(other, 50, edition=1)
        self.assertEqual(self.path.read_bytes(), other.read_bytes())

    def test_new_edition_changes_the_file(self):
        other = Path(self.folder.name) / "other.xlsx"
        wb.write_workbook(self.path, 50, edition=1)
        wb.write_workbook(other, 50, edition=2)
        self.assertNotEqual(self.path.read_bytes(), other.read_bytes())

    def test_column_letters(self):
        self.assertEqual([wb.column(i) for i in (0, 25, 26, 701)], ["A", "Z", "AA", "ZZ"])


if __name__ == "__main__":
    unittest.main()
