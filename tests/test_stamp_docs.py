# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

import stamp_docs  # noqa: E402

STAMP_FORMAT = re.compile(
    r"^_DRAFT - For internal use only\. Last modified: \d{4}-\d{2}-\d{2} \d{2}:\d{2} \S+ by mbitar\._$", re.MULTILINE
)


class StampTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)

    def write(self, text: str) -> Path:
        path = Path(self.folder.name) / "doc.md"
        path.write_text(text, encoding="utf-8")
        return path

    def test_replaces_existing_stamp(self):
        path = self.write("# Title\n\n_Last modified: 2000-01-01 00:00 UTC_\n\nBody\n")
        self.assertTrue(stamp_docs.stamp(path))
        text = path.read_text(encoding="utf-8")
        self.assertRegex(text, STAMP_FORMAT)
        self.assertNotIn("2000-01-01", text)
        self.assertTrue(text.endswith("Body\n"))

    def test_leaves_file_without_stamp_unchanged(self):
        path = self.write("# Title\n\nBody\n")
        self.assertFalse(stamp_docs.stamp(path))
        self.assertEqual(path.read_text(encoding="utf-8"), "# Title\n\nBody\n")

    def test_replaces_only_first_stamp(self):
        path = self.write("_Last modified: 2000-01-01 00:00 UTC_\n_Last modified: 1999-01-01 00:00 UTC_\n")
        stamp_docs.stamp(path)
        self.assertIn("1999-01-01", path.read_text(encoding="utf-8"))

    def test_restamps_new_form_with_another_name(self):
        path = self.write("_DRAFT - For internal use only. Last modified: 2000-01-01 00:00 UTC by mbitar._\n")
        self.assertTrue(stamp_docs.stamp(path, "jdoe"))
        text = path.read_text(encoding="utf-8")
        self.assertNotIn("2000-01-01", text)
        self.assertTrue(text.rstrip().endswith("by jdoe._"))
        self.assertEqual(text.count("DRAFT"), 1)


if __name__ == "__main__":
    unittest.main()
