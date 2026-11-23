# Disclaimers

_DRAFT - For internal use only. Last modified: 2026-11-23 11:37 EST by mbitar._

These disclaimers apply to everything in this repository and form part of its [license](LICENSE). Read them before you use any part of it.

## Proprietary and confidential

This repository is proprietary and confidential. FPT owns this solution. It is not open source. Nobody may use, copy, change or share any part of it without FPT's written permission.

## Proof of concept only

This repository describes a proof of concept. It is not a finished product and is not ready for production use. The proof of concept knowingly accepts weaknesses, including a shared password, a shared VPN certificate, a public IP address and local Terraform state that contains secrets. The [security page](docs/security.md) lists them. Do not put real or sensitive data on a deployment built from this repository without first making the production changes.

## No warranty

Everything here is provided as is, without any warranty. FPT does not promise that the code works, is secure, is free of errors, or suits any purpose.

## Cloud costs are your responsibility

Deploying this repository creates paid resources in Amazon Web Services. They keep charging every hour until they are deleted, whether or not anyone uses them. FPT is not responsible for any charge, including charges caused by mistakes in the code or the documentation, by resources that were not deleted, or by changes in AWS prices.

## Cost estimates are not quotes

The figures on the [costs page](docs/costs.md) are rough planning estimates based on list prices that FPT believed correct when writing them. They may be wrong, out of date or incomplete. They are not quotes, offers or commitments from anyone. Check every price in the AWS Pricing Calculator and in Microsoft's pricing pages before relying on it.

## Test results describe one environment

The [test results](docs/test-results.md) and the [live demo](docs/demo.md) record what happened once, on one Mac, on one home network, on one day. Other computers, networks, Regions, file sizes and software versions will give different results. Past results do not promise future behavior.

## Security is your responsibility

The security checks in this repository cover only the settings they name. Passing them does not make a deployment secure. Anyone who deploys this repository is responsible for reviewing it, hardening it, monitoring it, keeping its secrets safe, and meeting their own organization's security and compliance rules.

## Data loss

File shares, caches, VPNs and storage services can fail. Saves can be lost when a connection drops or a gateway stops. S3 versioning reduces the risk but does not remove it. Keep separate backups of anything important. FPT is not responsible for lost, damaged or exposed data.

## Not professional advice

Nothing here is legal, financial, tax, accounting, compliance or security advice. Cost and Usage Report data can affect financial decisions. Confirm any number that matters against an authoritative source.

## No affiliation

This repository is not made, endorsed, sponsored or supported by Amazon Web Services, Microsoft, Apple, HashiCorp or any other company it mentions. Amazon Web Services, AWS, Amazon S3, AWS Storage Gateway, AWS Client VPN and the AWS Architecture Icons are trademarks or property of Amazon.com, Inc. or its affiliates. Microsoft, Windows, Excel, Entra and Azure are trademarks of the Microsoft group of companies. Apple, Mac, macOS, Finder and Numbers are trademarks of Apple Inc. Terraform is a trademark of HashiCorp. All other names are the property of their owners and are used only to identify their products.

## Third-party material

The diagrams use AWS Architecture Icons under AWS's own terms. Terraform providers and other tools that this repository downloads or runs are covered by their own licenses. The [notice file](NOTICE.md) lists them. This repository's license grants no rights in any third-party material.

## Made-up sample data

The workbooks that the demo and the tests create hold invented data. The account IDs, services, usage amounts and costs in them do not describe any real account or real spending.

## Names, addresses and identifiers

Account names, IP addresses, gateway IDs and bucket names in the documentation come from a temporary test deployment. They are shown to make the documents concrete. Do not rely on them, and do not try to connect to them.

## Changes without notice

FPT may change, replace or remove any part of this repository, including these disclaimers, at any time and without notice.

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](LICENSE) and the [disclaimers](DISCLAIMER.md)._
