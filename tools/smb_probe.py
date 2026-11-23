# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.
"""Check that a file share server answers SMB 2 or SMB 3, without signing in.

The script sends one SMB2 NEGOTIATE request to TCP port 445 and prints the
protocol version the server chose. No user name or password is sent, so it is
safe to run against any server you are allowed to reach.

Usage (macOS, Windows or Linux):
    python tools/smb_probe.py 10.40.0.217
    python tools/smb_probe.py 10.40.0.217 --port 445 --timeout 8

Exit code 0 means the server answered with SMB 2 or SMB 3. Exit code 1 means it
did not answer, or something other than an SMB server answered.

A plain port test, such as nc or Test-NetConnection, is not enough on networks
whose router accepts every outgoing connection itself. This probe is reliable
on such networks, because only a real SMB server sends a valid SMB reply.
"""

from __future__ import annotations

import argparse
import os
import socket
import struct
import sys

# SMB 2.0.2, 2.1, 3.0 and 3.0.2. SMB 3.1.1 needs extra negotiate contexts and
# is left out to keep the request small; every SMB 3 server accepts 3.0.2.
DIALECTS = (0x0202, 0x0210, 0x0300, 0x0302)
SMB2_MAGIC = b"\xfeSMB"
HEADER_SIZE = 64


def build_negotiate(dialects: tuple[int, ...] = DIALECTS) -> bytes:
    """Return an SMB2 NEGOTIATE request wrapped in a 4-byte session header."""
    header = SMB2_MAGIC + struct.pack(
        "<HHIHHIIQIIQ",
        HEADER_SIZE,  # structure size
        0,  # credit charge
        0,  # status
        0,  # command: NEGOTIATE
        1,  # credits requested
        0,  # flags
        0,  # next command
        0,  # message ID
        0,  # process ID
        0,  # tree ID
        0,  # session ID
    ) + b"\x00" * 16  # signature
    body = struct.pack("<HHHHI", 36, len(dialects), 1, 0, 0)  # size, count, signing enabled, reserved, capabilities
    body += os.urandom(16)  # client GUID
    body += b"\x00" * 8  # client start time
    body += b"".join(struct.pack("<H", d) for d in dialects)
    message = header + body
    return b"\x00" + len(message).to_bytes(3, "big") + message


def parse_negotiate_response(data: bytes) -> tuple[int, str] | None:
    """Return (status, dialect text) from an SMB2 NEGOTIATE reply, or None if it is not one."""
    if len(data) < 4 + HEADER_SIZE + 6 or data[4:8] != SMB2_MAGIC:
        return None
    status = struct.unpack_from("<I", data, 4 + 8)[0]
    dialect = struct.unpack_from("<H", data, 4 + HEADER_SIZE + 4)[0]
    return status, f"{dialect >> 8}.{dialect & 0xFF:02x}"


def probe(host: str, port: int = 445, timeout: float = 8.0) -> tuple[int, str] | None:
    """Send the request and return the parsed reply, or None when no SMB reply came back."""
    with socket.create_connection((host, port), timeout=timeout) as conn:
        conn.sendall(build_negotiate())
        data = conn.recv(4096)
    return parse_negotiate_response(data)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check that a server answers SMB 2 or SMB 3, without signing in.")
    parser.add_argument("host", help="IP address or host name of the file share server")
    parser.add_argument("--port", type=int, default=445, help="TCP port, 445 by default")
    parser.add_argument("--timeout", type=float, default=8.0, help="seconds to wait for a reply, 8 by default")
    args = parser.parse_args(argv)

    try:
        result = probe(args.host, args.port, args.timeout)
    except (OSError, socket.timeout) as error:
        print(f"No SMB reply from {args.host}:{args.port}. The connection failed: {error}")
        return 1

    if result is None:
        print(f"Something answered on {args.host}:{args.port}, but it is not an SMB 2 or SMB 3 server.")
        return 1

    status, dialect = result
    print(f"The server answered with SMB {dialect} and status 0x{status:08x}.")
    return 0 if status == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
