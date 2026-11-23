# Pros and Cons

_DRAFT - For internal use only. Last modified: 2026-11-23 11:42 EST by mbitar._

This page weighs the S3 File Gateway approach against the other ways to let Excel users work on CUR files stored in S3.

[Back to the README](../README.md)

## S3 File Gateway, this project

### Pros

- **The files stay in S3.** Each file on the share is one object in the bucket, so CUR exports, Athena queries, lifecycle rules and backups keep working on the same data.
- **Nothing to install for file access.** Users map a network drive. Excel, VBA macros and existing workbook links work unchanged.
- **Fast after the first open.** Files in the gateway's cache open at disk speed. Saves finish at local speed, and the upload to S3 happens in the background.
- **Excel's lock prompt works.** The gateway supports Windows file locking, so a second user gets Excel's read-only prompt instead of silently overwriting someone else's changes.
- **Old versions are kept.** S3 versioning keeps the previous copy of every workbook for 30 days.
- **AWS supports it.** It is a managed AWS service with monitoring, software updates and AWS Support.
- **Repeatable.** Terraform creates and removes the whole setup, and tests check its security settings before anything is created.

### Cons

- **Every save uploads the whole file.** A 500 MB workbook saved ten times sends 5 GB to S3. Large files saved often keep the upload queue busy.
- **One gateway is one point of failure.** If the EC2 instance stops, the share is unavailable until it starts again. Files already in S3 are safe.
- **Locks only work within one gateway.** Users of a second gateway, or tools that write straight to S3, do not see the locks.
- **It needs a private network path.** Many networks block the file-sharing port, so users need a VPN or a Direct Connect link. That adds cost and setup.
- **Speed depends on distance.** SMB slows down as the delay between laptop and gateway grows. Users far from the AWS Region notice it.
- **Excel's limits stay.** A worksheet still holds at most 1,048,576 rows, and multi-gigabyte workbooks still take Excel a long time to load and save.
- **Changes made straight in S3 appear late.** The share checks the bucket every 5 minutes.
- **The Mac experience is rougher.** macOS apps need extra permissions, Open and Save windows cannot browse the server, and the Mac Numbers spreadsheet app converts files instead of editing them.

## Alternatives

| Option | How it works | Best for | Main drawbacks |
|---|---|---|---|
| **S3 File Gateway, this project** | A gateway on EC2 or in the office presents the bucket as a Windows file share. | Teams that need a shared drive and want the files to stay in S3. | Whole-file uploads, one gateway as a single point of failure, needs a private network path. |
| **Amazon FSx for Windows File Server** | A managed Windows file server, with AWS DataSync copying files to and from S3 on a schedule. | Workbooks that are saved many times a day, and teams that need high availability. | The files live in FSx, not S3, so the two copies drift between DataSync runs. It costs roughly twice as much. |
| **Amazon WorkSpaces** | Each user gets a Windows desktop in AWS, next to the data. | Remote users on slow connections, and data that must never reach laptops. | Users work in a remote desktop. The cost is per user, and Office licences are extra. |
| **rclone or Mountain Duck on each laptop** | A desktop app mounts the bucket as a drive on each computer. | One person working alone, at the lowest cost. | No file locking between users. Every laptop needs setup. Security teams often block rclone. |
| **Amazon Athena with Power Query** | Athena runs SQL on the CUR data in S3, and Excel pulls in only the summarized result. | Workbooks with millions of rows, where the analysis needs totals rather than every row. | The workflow changes. Macros that loop over raw rows need rewriting. |

## Recommendation

Use the S3 File Gateway for the shared-drive need, because it keeps the files in S3 and needs no change to how analysts work. For the largest CUR files, move the heavy lifting to Athena and Excel's Data Model over time. The gateway then holds the smaller summary workbooks, and the row limit and the upload cost stop mattering. Choose FSx for Windows instead only if users save very large workbooks many times a day and cannot accept a single gateway as a point of failure.

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](../LICENSE) and the [disclaimers](../DISCLAIMER.md)._
