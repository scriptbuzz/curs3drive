# Production Design

_DRAFT - For internal use only. Last modified: 2026-11-23 11:37 EST by mbitar._

This page describes the recommended changes for moving from the proof of concept to a production file share for the analysts. The design is a recommendation and is not built yet.

[Back to the README](../README.md)

![Recommended production design. Office and remote users reach an S3 File Gateway in a private subnet. The gateway joins a Microsoft Entra Domain Services domain and reaches S3 through VPC endpoints.](diagrams/architecture-production.svg)

## What changes from the proof of concept

| Area | Proof of concept | Production |
|---|---|---|
| Sign-in to the share | One shared guest password | Each user's own account, through the gateway's membership in a Microsoft Entra Domain Services domain |
| Folder permissions | Everyone can read and change everything | Windows folder permissions granted to Entra groups |
| Sign-in to the VPN | One shared client certificate | Microsoft Entra ID through SAML, so access is removed when the account is disabled |
| Office access | Not set up | AWS Site-to-Site VPN, or AWS Direct Connect when more bandwidth is needed |
| Public exposure | Public subnet, Elastic IP address, port 445 open to one address | Private subnet with no public address and no internet gateway |
| Gateway traffic to AWS | Through the internet gateway | Through VPC endpoints for S3 and Storage Gateway |
| Encryption keys | AWS-managed keys | A customer managed AWS KMS key for the bucket and the disks |
| Gateway size | m5.xlarge with a 300 GiB cache | m5.2xlarge or larger with a cache of 1 TiB or more, sized to a month of working files |
| Logging | Off | Client VPN connection logs, VPC flow logs, CloudTrail data events for the bucket, and gateway health logs in CloudWatch |
| Alarms | None | CloudWatch alarms for gateway health, cache upload backlog and cache hit rate |
| Terraform state | Local file | Encrypted S3 bucket with versioning and locking |

## Microsoft Entra ID

S3 File Gateway can join only an Active Directory domain, so it cannot use Microsoft Entra ID directly. Microsoft Entra Domain Services provides a managed Active Directory domain that stays in sync with Entra ID. The gateway joins that domain over a site-to-site VPN between the AWS VPC and the Azure virtual network, and users sign in to the share with their usual work accounts.

The AWS VPN Client signs users in through Entra ID with SAML. An Entra administrator creates an enterprise application for AWS Client VPN, and the VPN endpoint's authorization rules then allow only members of the analysts' Entra group.

## Steps to build it

1. Enable Microsoft Entra Domain Services, and connect its Azure virtual network to a new AWS VPC with AWS Site-to-Site VPN.
2. Create the VPC with private subnets in two Availability Zones and no internet gateway. Add a gateway VPC endpoint for S3 and an interface VPC endpoint for Storage Gateway.
3. Create a customer managed KMS key, and use it for the bucket and the EBS disks.
4. Deploy the gateway in a private subnet, activate it through the Storage Gateway VPC endpoint, and join it to the domain.
5. Create the file share with Active Directory sign-in, and grant folder access to Entra groups.
6. Create the Client VPN endpoint with SAML sign-in through Entra ID, and connect the office with Site-to-Site VPN or Direct Connect.
7. Turn on logging, create the CloudWatch alarms, and move the Terraform state to an encrypted S3 bucket.
8. Run the [test plan](test-plan.md) again against the production setup before users move over.

## Longer-term improvement for very large CUR files

For workbooks with millions of rows, consider moving the heavy lifting out of Excel. Amazon Athena can query the CUR data in S3 directly, and Excel's Power Query can pull in only the summarized result. The file share then holds smaller summary workbooks, which removes the row limit and the cost of uploading huge files on every save. See [Pros and cons](pros-and-cons.md#recommendation).

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](../LICENSE) and the [disclaimers](../DISCLAIMER.md)._
