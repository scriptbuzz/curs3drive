# Security Policy

_DRAFT - For internal use only. Last modified: 2026-11-23 11:37 EST by mbitar._

## Reporting a problem

If you find a security problem in this repository or in a deployment built from it, do not open a public issue. Email the repository owner directly, and describe what you found, how to reproduce it, and which files or resources it affects.

If you believe a guest password, a VPN profile file or a Terraform state file has been exposed, say so in the first line of the email. The owner will replace the password and the VPN certificates, as described in [Where each secret lives](docs/security.md#where-each-secret-lives).

## What this repository protects

The [security page](docs/security.md) lists the protections in place, the weaknesses the proof of concept accepts on purpose, and the changes that production needs.

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](LICENSE) and the [disclaimers](DISCLAIMER.md)._
