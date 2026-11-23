# Costs

_DRAFT - For internal use only. Last modified: 2026-11-23 11:37 EST by mbitar._

This page estimates what the proof of concept and the recommended production design cost per month. The prices are AWS on-demand list prices for the us-east-1 Region, and a month is 730 hours. Check them in the [AWS Pricing Calculator](https://calculator.aws/) before you rely on them, because prices change and differ by Region.

[Back to the README](../README.md)

## Proof of concept, as deployed

| Item | How it is charged | Monthly cost |
|---|---|---|
| EC2 instance for the gateway, m5.xlarge | $0.192 per hour | $140.16 |
| Cache disk, 300 GiB gp3 | $0.08 per GiB | $24.00 |
| Extra cache disk speed, 6,000 IOPS and 500 MiB/s | The first 3,000 IOPS and 125 MiB/s are included. Each extra IOPS costs $0.005 and each extra MiB/s costs $0.04. | $30.00 |
| System disk, 80 GiB gp3 | $0.08 per GiB | $6.40 |
| Elastic IP address | $0.005 per hour for a public IPv4 address | $3.65 |
| Client VPN endpoint attached to one subnet | $0.10 per hour | $73.00 |
| **Fixed monthly total** | | **$277.21** |

These items depend on use:

| Item | How it is charged | Example |
|---|---|---|
| Client VPN connections | $0.05 per hour for each connected user | 5 users connected 8 hours a day on 22 working days cost $44. |
| Data written to S3 through the gateway | $0.01 per GB, up to $125 per gateway per month | 200 saves of a 100 MB workbook write 20 GB and cost $0.20. |
| S3 storage | $0.023 per GB per month, including old versions | 50 GB of workbooks plus 50 GB of old versions cost $2.30. |
| Data downloaded by users | $0.09 per GB leaving AWS for the internet, after the first 100 GB each month | 300 GB of file opens cost $18. |
| S3 requests | $0.005 per 1,000 uploads and $0.0004 per 1,000 downloads | Usually less than $1. |
| AWS Certificate Manager | Imported certificates are free. | $0 |

**Stopping the costs.** Stopping the EC2 instance saves the instance cost, but the disks, the Elastic IP address and the VPN endpoint keep charging. To stop every charge, remove the deployment with `terraform destroy`, as described in the [deployment guide](deployment.md#remove-the-deployment).

## Recommended production design

This estimate is for 10 users, one office, and the design in [Production design](production.md).

| Item | Basis | Monthly cost |
|---|---|---|
| EC2 instance for the gateway, m5.2xlarge | $0.384 per hour | $280.32 |
| Cache disk, 1 TiB gp3, with extra speed | Storage plus extra IOPS and throughput | $111.92 |
| System disk, 80 GiB gp3 | | $6.40 |
| Client VPN endpoint | One subnet | $73.00 |
| Client VPN connections | 5 remote users, 8 hours a day, 22 days | $44.00 |
| Site-to-Site VPN to the office | $0.05 per hour | $36.50 |
| Site-to-Site VPN to Azure | $0.05 per hour | $36.50 |
| Interface VPC endpoint for Storage Gateway | $0.01 per hour in one Availability Zone, plus $0.01 per GB | about $8 |
| Gateway VPC endpoint for S3 | Free | $0 |
| Customer managed KMS key | $1 per key per month, plus requests | about $2 |
| CloudWatch logs and alarms | A few GB of logs and five alarms | about $5 |
| Storage Gateway writes, S3 storage and requests | Depends on use | about $10 to $50 |
| **Approximate AWS total** | | **$615 to $655** |

Microsoft charges separately for Microsoft Entra Domain Services and for the Azure VPN gateway on the Azure side of the site-to-site VPN. AWS Direct Connect replaces the office Site-to-Site VPN when the office needs more bandwidth, and it has its own port and data charges.

## How this compares with the alternatives

| Option | Typical monthly cost for 10 users | Main cost driver |
|---|---|---|
| S3 File Gateway on EC2, this project | $615 to $655 | The gateway instance and the VPN connections |
| Amazon FSx for Windows File Server, Multi-AZ, 1 TiB SSD, 256 MB/s | about $1,400 | Throughput capacity at about $4.50 per MB/s, and SSD storage at about $0.23 per GB, both for two Availability Zones |
| Amazon WorkSpaces, 10 Power bundles with 4 vCPUs and 16 GB of memory, billed monthly | about $800, plus Microsoft Office licences | One charge per user |
| rclone or Mountain Duck on each laptop, straight to S3 | S3 storage and downloads only, plus Mountain Duck licences | Data downloaded by users |

These figures are rough planning numbers, not quotes. The [pros and cons page](pros-and-cons.md) compares the options on more than cost.

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](../LICENSE) and the [disclaimers](../DISCLAIMER.md)._
