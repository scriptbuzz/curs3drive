# Changelog

_DRAFT - For internal use only. Last modified: 2026-11-25 12:38 EST by mbitar._

This file lists the notable changes to the repository, newest first.

## 2026-11-25

### Added

- A page that says what needs a Windows administrator on a production Windows 11 PC, with checks to paste into the PC.

### Changed

- The Windows guide now describes the profile menu of version 6 of the AWS VPN Client.
- Check 1 on the production PC page now also checks AppLocker and App Control, and ends with one answer for drive S:. Its result word `ADMIN` is now `WINDOWS ADMIN`.
- The production PC page now lists who fixes what, the network addresses and the sources.
- The two checks on the production PC page are now one interactive script with a menu, a progress bar, a status for each step and a cleanup option. The drive test asks for the gateway address, requires encryption, and disconnects the drive at the end.
- The production PC page now tells IT which steps may trigger security tools, and has a cleanup section.

## 2026-11-24

### Added

- A README section that compares the proof of concept with the production design, with the production diagram.
- Status, remote access, outbound traffic, instance metadata and cost in the comparison on the production design page.

### Fixed

- The production design page no longer says that the test plan has already run.
- The outbound rule recommended for production now includes the traffic that a domain-joined gateway needs.

## 2026-11-23

### Added

- Terraform configuration for an S3 File Gateway on EC2, with an encrypted and versioned S3 bucket, a least-privilege IAM role and an SMB file share that requires encryption.
- AWS Client VPN on TCP port 443, with certificates and a profile file created by Terraform, for networks that block the file-sharing port.
- A randomly generated guest password, so no password has to be typed into a file.
- Thirteen Terraform security tests that run with mock providers and need no AWS account.
- An SMB probe that checks a file server without signing in, and is reliable on networks that fake successful port tests.
- Drive-mapping scripts for Windows 11 and macOS.
- Architecture diagrams for the proof of concept and the production design, drawn with the official AWS Architecture Icons and checked automatically for clipped or overlapping text.
- Guides for deployment, connecting from Windows and macOS, security, costs, pros and cons, troubleshooting and the production design.
- Test results from the deployment in the sandbox01 account, and a test plan for the scenarios still open.
- A CI workflow that checks formatting, validates the configuration, runs the tests and scans the code with Checkov.
- A live demo script that runs the whole flow against the deployment and records it, a builder that turns the recording into an animated terminal view and a transcript page, and a generator for workbooks of made-up CUR data.

### Changed

- Made the repository proprietary, owned by FPT. Added a proprietary license, a set of disclaimers and a list of third-party material.
- Added a notice to every source file, and a footer to every document, saying that the material is confidential and that FPT owns the solution. The repository carries no copyright notice.
- Marked every document as a draft for internal use only. The stamp under each title now also records who made the last change.

### Removed

- Removed the deployment from the sandbox01 account, including the bucket and all its files. The README, the test results, the test plan and the deployment guide now say so.

### Fixed

- Closed port 80 after the gateway was activated.
- Corrected the removal instructions, which would have made Terraform try to delete the bucket instead of keeping it.

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](LICENSE) and the [disclaimers](DISCLAIMER.md)._
