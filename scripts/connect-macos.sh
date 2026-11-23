#!/usr/bin/env bash
# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.
# Opens the CUR file share in Finder on macOS.
#
# Connect the AWS VPN Client first. Finder then asks for the share's guest
# password and mounts the share at /Volumes/<share name>.
#
# Usage:
#   scripts/connect-macos.sh 10.40.0.217
#   scripts/connect-macos.sh 10.40.0.217 cur
#
# Get the gateway address by running this in the terraform folder:
#   terraform output -raw gateway_private_ip
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <gateway private IP address> [share name]" >&2
  exit 2
fi

address="$1"
share="${2:-cur}"
here="$(cd "$(dirname "$0")" && pwd)"

echo "Checking that ${address} answers as an SMB file server..."
if ! python3 "${here}/../tools/smb_probe.py" "${address}"; then
  echo "The gateway did not answer. Connect the AWS VPN Client and try again." >&2
  exit 1
fi

open "smb://smbguest@${address}/${share}"

cat <<EOF
Finder is opening the share. Sign in as smbguest with the guest password.

In an app's Open or Save window, press Cmd+Shift+G and type /Volumes/${share}
to reach the share, because those windows cannot browse the server entry itself.
EOF
