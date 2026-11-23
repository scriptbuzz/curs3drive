# Connect from Windows 11

_DRAFT - For internal use only. Last modified: 2026-11-23 11:37 EST by mbitar._

This guide maps the file share as drive S: on a Windows 11 laptop, so Excel can open and save the CUR workbooks.

[Back to the README](../README.md)

## What you need

- The VPN profile file, `cur-file-gateway.ovpn`, from the person who deployed the gateway.
- The gateway's private address, for example `10.40.0.217`, and its gateway ID, for example `sgw-C712B1AF`.
- The share's guest password, handed over through a password manager.
- Permission to install software on the laptop.

## Step 1: Install the AWS VPN Client

1. Download the AWS VPN Client for Windows from https://aws.amazon.com/vpn/client-vpn-download/.
2. Run the installer and accept the defaults.

## Step 2: Add the VPN profile

1. Open **AWS VPN Client** from the Start menu.
2. Choose **File**, then **Manage Profiles**, then **Add Profile**.
3. Type `CUR file share` as the display name, select the `.ovpn` file, and choose **Add Profile**.

## Step 3: Connect the VPN

Select the profile and choose **Connect**. The status changes to **Connected** within a few seconds.

## Step 4: Map the drive

Either run the script in this repository from PowerShell:

```powershell
.\scripts\connect-windows.ps1 -GatewayAddress 10.40.0.217 -GatewayId sgw-C712B1AF
```

The script checks that the gateway answers, asks for the guest password, and maps drive S:. If drive S: is taken, add `-DriveLetter T` or another free letter.

Or map it by hand in Command Prompt:

```bat
net use S: \\10.40.0.217\cur /user:sgw-C712B1AF\smbguest /persistent:yes
```

Enter the guest password when asked. The user name is the gateway ID, a backslash, and `smbguest`.

## Step 5: Work in Excel

Open workbooks from drive S: in File Explorer or from Excel's **File**, then **Open** menu. Save with Ctrl+S as usual. The save finishes at local speed, and the gateway uploads the file to S3 in the background.

If someone else already has the workbook open, Excel offers to open it read-only. That protection works because every user connects to the same gateway.

## Tips for large CUR workbooks

- Use 64-bit Excel. 32-bit Excel cannot use more than about 2 GB of memory.
- A worksheet holds at most 1,048,576 rows. For larger CUR data, load it into Excel's Data Model with Power Query instead of into worksheet cells.
- In VBA, read ranges into arrays instead of looping over cells, and set `Application.ScreenUpdating = False` and `Application.Calculation = xlCalculationManual` while a macro runs.
- Save less often during long edits. Every save uploads the whole workbook to S3.

## If something goes wrong

See [Troubleshooting](troubleshooting.md). The most common causes are a disconnected VPN, a mistyped user name, and a drive letter that is already in use.

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](../LICENSE) and the [disclaimers](../DISCLAIMER.md)._
