# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

import smb_probe  # noqa: E402


def fake_reply(dialect: int, status: int = 0) -> bytes:
    header = smb_probe.SMB2_MAGIC + struct.pack("<HHIHHIIQIIQ", 64, 0, status, 0, 1, 1, 0, 0, 0, 0, 0) + b"\x00" * 16
    body = struct.pack("<HHH", 65, 1, dialect) + b"\x00" * 58
    message = header + body
    return b"\x00" + len(message).to_bytes(3, "big") + message


class BuildNegotiateTest(unittest.TestCase):
    def test_session_header_length_matches_message(self):
        packet = smb_probe.build_negotiate()
        self.assertEqual(int.from_bytes(packet[1:4], "big"), len(packet) - 4)

    def test_message_starts_with_smb2_magic(self):
        self.assertEqual(smb_probe.build_negotiate()[4:8], b"\xfeSMB")

    def test_all_dialects_are_offered(self):
        packet = smb_probe.build_negotiate()
        count = struct.unpack_from("<H", packet, 4 + 64 + 2)[0]
        offered = struct.unpack_from(f"<{count}H", packet, len(packet) - 2 * count)
        self.assertEqual(offered, smb_probe.DIALECTS)


class ParseResponseTest(unittest.TestCase):
    def test_reads_dialect_and_status(self):
        self.assertEqual(smb_probe.parse_negotiate_response(fake_reply(0x0302)), (0, "3.02"))

    def test_reports_non_zero_status(self):
        status, _ = smb_probe.parse_negotiate_response(fake_reply(0x0300, status=0xC0000022))
        self.assertEqual(status, 0xC0000022)

    def test_rejects_non_smb_bytes(self):
        self.assertIsNone(smb_probe.parse_negotiate_response(b"HTTP/1.1 400 Bad Request\r\n\r\n" + b"x" * 80))

    def test_rejects_short_reply(self):
        self.assertIsNone(smb_probe.parse_negotiate_response(b"\x00\x00\x00\x04\xfeSMB"))


if __name__ == "__main__":
    unittest.main()
