# Troubleshooting

_DRAFT - For internal use only. Last modified: 2026-11-23 11:42 EST by mbitar._

Each section below starts with what the user sees, then explains the cause and the fix.

[Back to the README](../README.md)

## A port test succeeds but the share does not answer

**Cause.** Some routers and internet providers accept every outgoing connection themselves and pass on only web traffic. A port test such as `nc` or `Test-NetConnection` then reports success for any address and port. The test network in this project behaved this way.

**How to tell.** Test a server that certainly offers no file sharing. If this also reports success, port tests prove nothing on that network:

```bash
nc -vz -G 4 8.8.8.8 445
```

**Fix.** Use the SMB probe, which only a real SMB server can answer:

```bash
python3 tools/smb_probe.py 10.40.0.217
```

If the probe gets no reply from the public address, connect through the Client VPN.

## Terraform stops with an expired single sign-on token

**What you see.** `Error when retrieving token from sso: Token has expired and refresh failed`.

**Fix.** Sign in again, and finish the approval in the browser window that opens:

```bash
aws sso login --profile sandbox01
```

## Terraform stops because the local disk was not found

**Cause.** The gateway reports its cache disk under a different path than the configuration expects.

**Fix.** Follow [If the cache disk is not found](deployment.md#if-the-cache-disk-is-not-found) in the deployment guide.

## The VPN connects but the share does not open

1. Check that the VPN shows **Connected** in the AWS VPN Client.
2. Run the SMB probe against the gateway's private address. A reply of SMB 3.02 with status 0 means the gateway and the network path are fine.
3. Check the address: use the private address, such as `10.40.0.217`, not the public one.
4. Check the user name: `smbguest` on a Mac, and `<gateway ID>\smbguest` on Windows.

## Windows says the drive letter is already in use

Run the connection script with another letter, for example `-DriveLetter T`, or remove the old mapping with `net use S: /delete`.

## Excel opens files in Protected View and blocks macros

**Cause.** Windows treats a share addressed by IP address as an internet location, and Microsoft blocks macros in files from the internet by default.

**Fix.** In Excel, open **File**, **Options**, **Trust Center**, **Trust Center Settings**, **Trusted Locations**. Tick **Allow Trusted Locations on my network**, then add `\\10.40.0.217\cur`. For many laptops, an administrator can add the share to the Local intranet zone through Group Policy instead. Scenario W5 in the [test plan](test-plan.md) checks this.

## On a Mac, the save window shows the server as disconnected

**Cause.** Open and Save windows cannot browse a server entry. They can only use a mounted share.

**Fix.** Press Cmd+Shift+G in the window, type `/Volumes/cur`, and press Enter. [Connect from macOS](connect-macos.md#saving-from-excel-or-the-mac-numbers-spreadsheet-app) has the details.

## On a Mac, the Numbers spreadsheet app always asks where to save

**Cause.** The Mac Numbers spreadsheet app converts Excel files into its own format and cannot save `.xlsx` files in place.

**Fix.** Use **File**, **Export To**, **Excel**.

## On a Mac, an app or Terminal says "Operation not permitted" on the share

**Cause.** macOS asks before an app may use network volumes, and the app has not been allowed yet.

**Fix.** Open the file from inside the app and choose **Allow** when macOS asks. The permission then appears under **System Settings**, **Privacy & Security**, **Files & Folders**.

## Files whose names start with `._`, or `.DS_Store` files, appear in the bucket

**Cause.** macOS writes these files onto network shares to store Finder settings and extra file details.

**Fix.** They are harmless, and Windows users do not see them. To stop `.DS_Store` files, run `defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true` on each Mac, then sign out and back in.

## A large file shows several versions in S3 after one copy

**Cause.** The gateway uploaded the file while it was still being written.

**Fix.** Nothing is needed. The final version is complete, and the 30-day cleanup rule deletes the partial versions.

## A file added straight to S3 does not appear on the share

**Cause.** The gateway checks the bucket for changes every 5 minutes.

**Fix.** Wait 5 minutes. To refresh at once, run:

```bash
aws storagegateway refresh-cache --file-share-arn <file share ARN>
```

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](../LICENSE) and the [disclaimers](../DISCLAIMER.md)._
