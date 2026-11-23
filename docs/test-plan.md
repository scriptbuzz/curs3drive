# Test Plan

_DRAFT - For internal use only. Last modified: 2026-11-23 11:37 EST by mbitar._

These scenarios have not run. The deployment was removed on 23 November 2026, and every scenario needs a live gateway, VPN and bucket, so running them means deploying again with the [deployment guide](deployment.md). They cover what the [completed tests](test-results.md) left open: Windows 11 with Excel and VBA, large files, data safety, recovery from failures, and security.

[Back to the README](../README.md)

## How to read this plan

- **Priority.** "Must" scenarios decide whether the approach works for the analysts. "Should" scenarios find problems that production would hit. "Could" scenarios are useful but can wait.
- **Runs on.** "Windows" needs a Windows 11 laptop with Excel. "Mac" runs on the Mac used so far. "AWS" runs with the AWS CLI from any computer that can sign in to the sandbox01 account.
- Record each result in [Test results](test-results.md) with the date, the measured numbers and any error message.

## Recommended order

1. Run the AWS and Mac scenarios first. They need no extra hardware and take about an hour.
2. Run the Windows scenarios W1 to W6 with one Windows laptop.
3. Run W7, L1 and L2 with two Windows laptops, or with a colleague.
4. Run the resilience scenarios last, because they restart the gateway.
5. Run O3, the teardown rehearsal, and decide whether to keep the bucket.

## Windows 11 with Excel

| ID | Priority | Runs on | Scenario and steps | Passes when |
|---|---|---|---|---|
| W1 | Must | Windows | Install the AWS VPN Client, connect, and map drive S: with `scripts/connect-windows.ps1`. Restart the laptop and connect the VPN again. | Drive S: shows the workbooks before and after the restart. |
| W2 | Must | Windows | Open the 121 MB workbook from drive S: in Excel. Time the open with a stopwatch, close it, and open it a second time. | Both opens succeed. The times are recorded. |
| W3 | Must | Windows | Change one cell and press Ctrl+S. | Excel saves without a Save As window. A new version appears in S3 and the previous version is kept. |
| W4 | Must | Windows | Open a workbook that contains a VBA macro, run the macro, save it as `.xlsm`, close it and reopen it. | The macro runs, the file saves, and the macro is still in the file after reopening. |
| W5 | Must | Windows | Check whether Excel opens files from `\\10.40.0.217\cur` in Protected View and blocks macros. Windows treats a share addressed by IP address as an internet location, and Microsoft blocks macros in files from the internet by default. | Either macros run, or the fix is found and recorded. The usual fix is adding the share to Excel's Trusted Locations with "Allow trusted locations on my network" ticked, or adding it to the Local intranet zone through Group Policy. |
| W6 | Must | Windows | Open a workbook, then close Excel. Check the bucket for Excel's temporary files, whose names start with `~$`. | No temporary files remain in the bucket after Excel closes. |
| W7 | Must | Two Windows laptops | User A opens a workbook. User B opens the same workbook. | User B gets Excel's "locked for editing" prompt and can open it read-only. User B is told when User A closes it. |

## Large files

| ID | Priority | Runs on | Scenario and steps | Passes when |
|---|---|---|---|---|
| L1 | Must | Windows | Build a workbook with 4 million CUR rows split across four worksheets. Open it from the share, run a VBA macro that totals cost by account, and save it. | It opens, the macro finishes, and the save completes. Open time, macro time, save time and Excel's peak memory use are recorded. |
| L2 | Should | Windows | Load a 4-million-row CUR CSV file from the share into Excel's Data Model with Power Query, and build a PivotTable of cost by service. | The load finishes and the PivotTable matches a total computed with Athena or a script. The load time is recorded. |
| L3 | Should | Windows and AWS | Save a workbook of about 500 MB. Measure how long the gateway takes to upload it, by watching for the new version in S3 and the gateway's `CachePercentDirty` metric in CloudWatch. | The upload finishes, and the time is recorded. Excel did not wait for it. |

## Data safety

| ID | Priority | Runs on | Scenario and steps | Passes when |
|---|---|---|---|---|
| D1 | Must | Mac and AWS | Compute the SHA-256 checksum of a workbook on the Mac, copy it to the share, download it again from S3 with the AWS CLI, and compute the checksum again. | Both checksums match. |
| D2 | Must | AWS and Mac | In the S3 console, restore an older version of a workbook by copying it over the current one. Wait 5 minutes and open it from the share. | The share shows the restored content. |
| D3 | Should | Mac and AWS | Delete a workbook on the share. Check that S3 shows a delete marker. Remove the delete marker in the S3 console. | The file reappears on the share within 5 minutes. |
| D4 | Should | Mac | Rename a folder that holds several large workbooks, and move a workbook into another folder. | The S3 object names change to match, with no leftover copies. The time for the folder rename is recorded. |
| D5 | Could | Mac or Windows | Save files whose names contain spaces, accented letters such as é and ü, and a full path longer than 200 characters. | Every file opens again from the share with the same name, and the S3 object names are correct. |

## Changes made straight in S3

| ID | Priority | Runs on | Scenario and steps | Passes when |
|---|---|---|---|---|
| S1 | Must | AWS and Mac | Upload a new file straight to the bucket with `aws s3 cp`, then check the share every minute. | The file appears on the share within 5 minutes. The delay is recorded. |
| S2 | Should | AWS and Windows | Open a workbook from the share, then overwrite the same object straight in S3. Save the workbook in Excel. | The result is recorded. The expected result is that the last save wins, with the overwritten version kept as an older S3 version. Neither copy is corrupted. |

## Recovery from failures

| ID | Priority | Runs on | Scenario and steps | Passes when |
|---|---|---|---|---|
| R1 | Must | Windows | Start saving a large workbook, then disconnect the VPN during the save. Reconnect and open the workbook again. | Excel reports an error instead of claiming success. The file on the share is either the old or the new version, never a damaged one. |
| R2 | Should | AWS | With nobody connected, restart the gateway's EC2 instance. Time how long until the share answers the SMB probe again. | The share comes back on its own, and mapped drives work again without being mapped again. The time is recorded. |
| R3 | Should | Windows and AWS | Save a large workbook and restart the gateway instance before the upload finishes. | After the restart, the gateway finishes the upload and S3 has the complete new version. |
| R4 | Could | Mac or Windows | Put the laptop to sleep for 15 minutes with the share open, then wake it and reconnect the VPN. | The share works again without being mapped again. |

## Security

| ID | Priority | Runs on | Scenario and steps | Passes when |
|---|---|---|---|---|
| X1 | Must | Mac | Connect to the share with a wrong password. | The share refuses the connection. |
| X2 | Must | AWS and Mac | Replace the guest password with `terraform apply -replace=random_password.smb_guest`. Try the old password, then the new one. | The old password is refused and the new one works. This also replaces the password that appeared in a terminal transcript. |
| X3 | Must | AWS | Check that nothing in the bucket can be read without AWS credentials: request an object's public URL with `curl` and read the bucket's public access block. | The request returns HTTP 403, and all four public access blocks are on. |
| X4 | Should | Mac | Connect from a network whose address is not in `allowed_client_cidrs`, such as a phone hotspot, without the VPN. Run the SMB probe against the public address. Then connect the VPN and run the probe against the private address. | No SMB reply without the VPN. An SMB reply through the VPN. |
| X5 | Should | Mac | With the VPN connected, list the routes the VPN added. | Only 10.40.0.0/16 goes through the tunnel. |
| X6 | Should | Mac | Try to connect with an SMB client that does not encrypt, for example by forcing SMB 2.1. | The gateway refuses the session. |
| X7 | Should | AWS | Use the IAM policy simulator to check whether the gateway's role can read a different bucket. | The simulator denies it. |
| X8 | Could | Mac | Edit a copy of the VPN profile to remove the client certificate and try to connect. | The VPN refuses the connection. |

## Operations and cost

| ID | Priority | Runs on | Scenario and steps | Passes when |
|---|---|---|---|---|
| O1 | Should | AWS | Read the gateway's CloudWatch metrics for the test period: `CacheHitPercent`, `CachePercentDirty`, `CloudBytesUploaded` and `CloudBytesDownloaded`. | All four have data, and the values match the tests that ran. |
| O2 | Should | AWS | After at least 24 hours, compare the actual daily cost in Cost Explorer with the [cost estimate](costs.md). | The actual cost is within 20 percent of the estimate, or the difference is explained. |
| O3 | Must | AWS | Run `terraform plan -destroy`, and decide whether to keep the bucket, as described in the [deployment guide](deployment.md#remove-the-deployment). | The plan deletes only this project's resources, and the bucket decision is recorded. |

## Exit criteria

The proof of concept succeeds when every "Must" scenario passes, or fails with a documented fix. In particular:

- Excel on Windows opens, edits and saves the 121 MB workbook in place, with no Save As window.
- VBA macros run on files from the share, with the trust setting from W5 documented.
- A second user gets Excel's lock prompt.
- No data is lost or damaged when the VPN drops or the gateway restarts during a save.
- The guest password has been replaced.

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](../LICENSE) and the [disclaimers](../DISCLAIMER.md)._
