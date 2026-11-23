# Connect from macOS

_DRAFT - For internal use only. Last modified: 2026-11-23 11:42 EST by mbitar._

This guide opens the file share in Finder on a Mac. It also covers two macOS behaviors that stop Excel and the Mac Numbers spreadsheet app from saving to the share until you work around them.

[Back to the README](../README.md)

## What you need

- The VPN profile file, `cur-file-gateway.ovpn`.
- The gateway's private address, for example `10.40.0.217`.
- The share's guest password.
- Your Mac's administrator password, for installing the VPN app.

## Step 1: Install the AWS VPN Client

With Homebrew:

```bash
brew install --cask aws-vpn-client
```

Or download the macOS installer from https://aws.amazon.com/vpn/client-vpn-download/ and open it. Either way, macOS asks for your Mac's password, because the app installs a helper that creates the VPN connection.

## Step 2: Add the VPN profile and connect

1. Open **AWS VPN Client** from Applications. Press Cmd+Space, type the name, and press Enter.
2. Choose **File**, then **Manage Profiles**, then **Add Profile**.
3. Type `CUR file share` as the display name. For the configuration file, click the folder icon, press Cmd+Shift+G, paste the file's full path, and press Enter.
4. Choose **Add Profile**, then **Done**.
5. Select the profile and choose **Connect**. If macOS asks to allow VPN configurations, choose **Allow**.

The VPN has no password. It signs in with the certificate inside the profile file.

## Step 3: Open the share in Finder

1. Click the Finder icon in the Dock and press Cmd+K.
2. Enter `smb://smbguest@10.40.0.217/cur` and click **Connect**.
3. Choose **Registered User**, enter `smbguest` as the name and the guest password, and click **Connect**.

The share opens as a window named **cur** and is mounted at `/Volumes/cur`.

The script in this repository checks the gateway and opens Finder for you:

```bash
scripts/connect-macos.sh 10.40.0.217
```

## Saving from Excel or the Mac Numbers spreadsheet app

### Open and Save windows cannot browse the server

In an app's Open or Save window, the sidebar shows the server as `10.40.0.217`, and clicking it shows the server as disconnected. That entry is for browsing servers, which these windows cannot do. Go to the mounted share instead: press **Cmd+Shift+G**, type `/Volumes/cur`, and press Enter.

To show **cur** in the sidebar permanently, open Finder, choose **Finder**, then **Settings**, then **Sidebar**, and tick **Connected servers**.

### Apps need permission to use network volumes

macOS asks before an app may read or write a network share. If an app was never asked, it can open a file you double-click in Finder, but it cannot save next to that file, so it shows a Save As window instead. Open the file from inside the app, with **File**, then **Open**, and choose **Allow** when macOS asks about network volumes. The permission then appears under **System Settings**, **Privacy & Security**, **Files & Folders**.

### The Mac Numbers spreadsheet app converts Excel files

The Mac Numbers spreadsheet app does not edit `.xlsx` files. It converts them into Numbers documents when it opens them, so **Save** always asks where to store a Numbers file. To write the workbook back to the share as an Excel file:

1. Choose **File**, then **Export To**, then **Excel**, and click **Next**.
2. Press Cmd+Shift+G, type `/Volumes/cur`, and press Enter.
3. Keep the file name, click **Export**, and choose **Replace**.

In the tests, the Mac Numbers spreadsheet app took about 3 minutes to open the [114 MB workbook](test-results.md#large-workbook-test-the-114-mb-file), and the conversion took most of that time. The file itself copied from the share in 21 seconds. Numbers cannot run VBA macros, so use Windows for the real work.

## Stop the Mac from writing hidden files to the share

macOS writes `.DS_Store` files, and files whose names start with `._`, onto network shares. They end up in the S3 bucket. Windows users do not see them. To stop the `.DS_Store` files on your Mac, run:

```bash
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
```

Then sign out and back in.

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](../LICENSE) and the [disclaimers](../DISCLAIMER.md)._
