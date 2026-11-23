# Test Results

_DRAFT - For internal use only. Last modified: 2026-11-23 11:42 EST by mbitar._

This page records every test run against the proof of concept, with the measured results. All tests ran on 23 November 2026 against the deployment in the sandbox01 account, in us-east-1. Scenarios that still need to run are in the [test plan](test-plan.md).

[Back to the README](../README.md)

## Summary

| Area | Result |
|---|---|
| **Large workbook, the 114 MB file** | **Passed on macOS. The copy from the share took 20.8 seconds, and the Mac Numbers spreadsheet app took about 3 minutes to open it. See [Large workbook test](#large-workbook-test-the-114-mb-file).** |
| Terraform validation | Passed. |
| Terraform security tests | 13 of 13 passed. |
| Python tool tests | 16 of 16 passed. |
| Live demo | Every step succeeded in 32 seconds. See [Live demo](demo.md). |
| Diagram layout checks | Both diagrams passed with no clipped or overlapping text. |
| Deployment | 41 resources created with no errors. Port 80 was closed afterwards. |
| File share over the public internet | Failed from the test network. The router drops all traffic on port 445. |
| File share through Client VPN | Passed. SMB 3.1.1 with AES-128-GCM encryption. |
| Copy, open and save from macOS | Passed, after the workarounds for the macOS permission and for the Mac Numbers spreadsheet app. |
| Windows 11 with Excel and VBA | Not tested. The deployment was removed before this test ran. |
| Removal | Passed. Terraform deleted all 40 resources, and a check found nothing left in the account. See [Removal](#removal). |

## Large workbook test (the 114 MB file)

This section collects every result for the largest workbook tested, so they are in one place. During testing it was called the 114 MB file. S3 recorded its exact size as 121,576,278 bytes, which is 115.9 MiB, and its name was `agency-b-cur-2026-10.xlsx`. All tests ran on 23 November 2026 from the Mac, over a home internet connection of about 65 Mbit/s, through AWS Client VPN.

| Test | Time | Result |
|---|---|---|
| Download straight from S3 with the AWS CLI, without the VPN | 15 seconds | Passed. This sets the speed of the home connection, about 65 Mbit/s, as the baseline. |
| Copy the workbook to the share in Finder | Not timed | Passed. The workbook appeared in S3 at its full size. |
| Copy the workbook from the share through the VPN with `cp` | 20.8 seconds | Passed. The VPN and SMB add about 6 seconds to the direct S3 download. |
| Open the workbook in the Mac Numbers spreadsheet app from the share | About 3 minutes | Passed, but slowly. Numbers spends about 2 minutes 40 seconds converting the file into its own format. Excel does not convert `.xlsx` files, so this delay does not apply to Excel. |
| Count the S3 versions created by one copy | | The bucket received five versions while the copy ran, at 16 MB, 50 MB, 84 MB, 117 MB and the final size. The gateway uploads a large file in stages, and the 30-day cleanup rule deletes the partial versions. |
| Open, edit and save the workbook in Excel on Windows 11, and run VBA on it | | Not tested. The deployment was removed first. Scenarios in the [test plan](test-plan.md) cover it. |

**What this means for Excel users.** A workbook of this size reaches a laptop in about the time a direct S3 download takes, plus a few seconds. Excel opens it without the conversion step that slowed the Mac Numbers spreadsheet app. Each save uploads the whole file again, and S3 keeps the partial versions for 30 days.

## Test environment

| Part | Version or setting |
|---|---|
| Computer running Terraform and the client tests | Mac with Apple silicon, on a home network behind a router at 192.168.8.1 |
| Terraform | 1.15.7, with AWS provider 6.73.0, random 3.9.1, tls 4.4.2 and local 2.9.1 |
| AWS CLI | 2.35.14 |
| AWS VPN Client for macOS | 6.3.2 |
| Gateway software | 2.1.16 |
| Gateway instance | m5.xlarge with a 300 GiB gp3 cache disk at 6,000 IOPS and 500 MiB/s |

## Automated tests

### Terraform validation and formatting

`terraform fmt -check -recursive` reported no changes, and `terraform validate` reported a valid configuration.

### Terraform security tests

`terraform test` ran 13 plan-only tests with mock providers. All 13 passed.

| Test | What it proves |
|---|---|
| `file_share_requires_smb_encryption` | The gateway refuses unencrypted SMB sessions. |
| `smb_port_open_only_to_listed_addresses` | Port 445 is open only to the listed addresses, with one rule each. |
| `activation_port_closed_by_default` | Port 80 stays closed unless activation addresses are listed. |
| `open_internet_is_rejected` | A rule that opens port 445 to 0.0.0.0/0 is rejected before deployment. |
| `short_guest_password_is_rejected` | A guest password shorter than 6 characters is rejected. |
| `cache_smaller_than_aws_minimum_is_rejected` | A cache disk smaller than AWS's 150 GiB minimum is rejected. |
| `disks_are_encrypted` | Both the cache disk and the system disk are encrypted. |
| `bucket_is_private_encrypted_and_versioned` | All public access blocks are on, default encryption and versioning are on, and object ACLs are off. |
| `existing_bucket_is_left_alone` | With `create_bucket = false`, Terraform creates and changes no bucket resources. |
| `gateway_role_is_limited_to_one_bucket` | Only Storage Gateway, acting for this account, can use the role, and the role covers one bucket with no wildcard actions. |
| `file_share_uses_locking_and_refresh` | File locking is on, and the share checks S3 for new files every 5 minutes. |
| `vpn_uses_tcp_443_and_split_tunnel` | The VPN uses TCP port 443, sends only VPC traffic through the tunnel, and lets users reach only the VPC. |
| `vpn_profile_file_is_private` | The VPN profile file can be read only by its owner. |

### Python tool tests

`python -m unittest discover -s tests` ran 16 tests for the SMB probe, the sample workbook generator and the document stamper. All 16 passed.

### Diagram layout checks

`tools/build_diagrams.py` measured every text element in headless Chrome. The proof-of-concept diagram has 65 text elements and the production diagram 87, and neither has text that leaves its box, runs off the canvas, or overlaps other text, an icon or a step marker. A planted test diagram with deliberate mistakes confirmed that the checker reports both kinds of problem.

## Deployment

| Step | Result |
|---|---|
| First plan and apply | 25 resources created. Terraform activated the gateway over port 80 from the Mac's public address. |
| Cache disk | The gateway reported the cache disk at `/dev/nvme1n1`, as the configuration expected. The gateway showed 322,122,547,200 bytes (300 GiB) of cache. |
| Gateway state | Running, software version 2.1.16. |
| File share | SMB share available. |
| Closing port 80 | The second apply deleted 1 security group rule. The remaining inbound rule allows only port 445 from 31.13.189.254/32. |
| Client VPN | 16 resources created. Attaching the endpoint to the subnet took 9 minutes 8 seconds. The endpoint showed as available on TCP port 443, and the authorization rule for 10.40.0.0/16 showed as active. |
| VPN profile file | Written with owner-only permissions (`-rw-------`). It contains the certificate authority certificate, the client certificate and the client key. |

## Network tests

### The test network fakes successful connections

A plain port test from the Mac to the gateway's public address reported success on port 445, on port 80 after it was closed, and on port 8080, which was never open. Port tests to unrelated servers on ports they do not serve also reported success: 8.8.8.8 on port 445, 1.1.1.1 on port 8443 and 9.9.9.9 on port 3389. A test to an address that routes nowhere, 192.0.2.1, timed out.

**Conclusion.** The router or the internet provider accepts every outgoing TCP connection itself and passes only web traffic on. Port tests prove nothing on this network.

### SMB over the public internet

The SMB probe sent a real SMB handshake to the gateway's public address on port 445. No reply came back within 8 seconds.

**Conclusion.** Users on this network cannot reach the share without the VPN. This result is the reason the proof of concept added AWS Client VPN.

### SMB through the VPN

| Check | Result |
|---|---|
| Address assigned to the Mac | 10.50.0.34, from the VPN range 10.50.0.0/22 |
| SMB probe to 10.40.0.217 | The gateway answered with SMB 3.02 and status 0, which means success. |
| Session negotiated by Finder | SMB 3.1.1, encrypted with AES-128-GCM |

## File tests from macOS

| Test | Result |
|---|---|
| Copy three workbooks to the share in Finder | All three appeared in the S3 bucket. |
| Copy the 114 MB workbook | Passed. The [Large workbook test](#large-workbook-test-the-114-mb-file) section has every result for this file. |
| Save from the Mac Numbers spreadsheet app after opening a workbook from Finder | Failed at first. Numbers showed a save window, and that window showed the server as disconnected. Numbers converts Excel files into its own format, so it always asks where to save. The save window cannot browse the server entry, only the mounted share. |
| Export from the Mac Numbers spreadsheet app to the share, reached with Cmd+Shift+G and `/Volumes/cur` | Passed. S3 shows a new version of the workbook, 8,583 bytes, saved at 15:24:24 UTC. The previous 7,613-byte version was kept. |
| Hidden macOS files | `.DS_Store` files and files whose names start with `._` appeared in the bucket. |

## Live demo runs

`scripts/demo.sh` ran twice at 11:02 and 11:04 EST in the Mac's Terminal. Both runs completed every step. The second run is the recorded one, shown on the [demo page](demo.md).

| Check | Result of the recorded run |
|---|---|
| SMB session | SMB 3.1.1, encrypted with AES-128-GCM |
| Gateway | Running, software 2.1.16, 300 GiB cache with 0.06 percent used and nothing waiting for upload |
| Copy a 6,547,156-byte workbook to the share | 10.9 seconds |
| Time until the new file was in S3, counted from the end of the copy | 1 second |
| Object in S3 | 6,547,156 bytes, encrypted with AES256 |
| Checksum of the file downloaded from S3 | Identical to the original |
| Save an edited version through the share | The copy took 10.1 seconds, the new version was in S3 1 second later, and S3 kept the earlier versions. |
| File written straight to S3 | Appeared on the share less than a second after a cache refresh was requested |
| Whole run | 32 seconds |

**Finding: one save from the Mac creates two identical S3 versions.** In both runs, each copy from the Mac produced two S3 versions of the same size, about 6 seconds apart. The most likely cause is that macOS changes the file's details, such as its timestamps, right after writing it, and the gateway records those details by writing the object again. The extra versions cost storage until the 30-day cleanup rule deletes them. Scenario W3 in the [test plan](test-plan.md) checks whether Excel on Windows causes the same.

## Removal

The deployment was removed on 23 November 2026, after the live demo. The scenarios in the [test plan](test-plan.md) did not run first.

| Step | Result |
|---|---|
| Empty the bucket | All 80 entries were permanently deleted: 63 file versions and 17 delete markers. Nothing was kept. |
| `terraform destroy` | 40 resources were deleted with no errors. Terraform deleted the bucket once it was empty. |
| Check for leftovers in AWS | No gateway, EC2 instance, EBS volume, Elastic IP address, Client VPN endpoint, VPC, ACM certificate, IAM role, S3 bucket, log group or snapshot from the project remained. |
| Clean up the Mac | The Terraform state files, the saved plans, the downloaded providers and the VPN profile file were deleted. The AWS VPN Client was uninstalled with Homebrew, and its leftover logs and settings were deleted. |

## Problems found and fixed

| Problem | Fix |
|---|---|
| Expired AWS single sign-on session | Signed in again with `aws sso login --profile sandbox01`. |
| Port tests gave false successes | Added the SMB probe, which only a real SMB server can answer. |
| Port 445 blocked on the home network | Added AWS Client VPN on TCP port 443. |
| The save window could not reach the share | Reached the mounted share with Cmd+Shift+G and `/Volumes/cur`. |
| The Mac Numbers spreadsheet app cannot save `.xlsx` files | Used Export To, then Excel, which writes an `.xlsx` file. |
| macOS blocked this computer's command-line tools from reading the share | Ran the copy test in the user's own Terminal, which macOS allowed. The [macOS guide](connect-macos.md) explains the network volume permission. |
| A first draft of the deployment guide would have deleted the bucket on removal | Replaced the instruction with `terraform state rm` commands that keep the bucket. |

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](../LICENSE) and the [disclaimers](../DISCLAIMER.md)._
