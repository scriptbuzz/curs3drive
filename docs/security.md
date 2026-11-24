# Security

_DRAFT - For internal use only. Last modified: 2026-11-24 08:02 EST by mbitar._

This page lists the protections the proof of concept has, the weaknesses it accepts on purpose, and what production must change. CUR files show what an organization spends on AWS and on which accounts, so treat them as confidential business data.

[Back to the README](../README.md)

## Protections in place

| Area | Protection | How it is checked |
|---|---|---|
| Data in transit, laptop to gateway | Every SMB connection must be encrypted. The gateway refuses unencrypted sessions. | The Terraform tests check the setting. The Mac in the tests negotiated SMB 3.1.1 with AES-128-GCM encryption. |
| Data in transit, over the internet | File-sharing traffic travels inside the Client VPN tunnel, which uses TLS. | The Terraform tests check TCP port 443 and split tunnelling. |
| Data in transit, gateway to S3 | The gateway talks to S3 over HTTPS. | AWS enforces this for Storage Gateway. |
| Data at rest on the gateway | The cache disk and the system disk are encrypted with EBS encryption. | The Terraform tests check both disks. |
| Data at rest in S3 | New objects are encrypted with S3-managed keys (SSE-S3). All four S3 public access blocks are on, and object ACLs are disabled. | The Terraform tests check all of these. |
| Recovery from bad saves | S3 versioning keeps every previous version for 30 days. | The Terraform tests check versioning. The save test confirmed that the old version was kept. |
| Network exposure | Port 445 is open only to the listed client addresses and to VPN users. Port 80 is closed after activation. A rule that opens port 445 to the whole internet is rejected before deployment. | The Terraform tests check all three. |
| Gateway permissions | The IAM role can be used only by the Storage Gateway service, only for this AWS account, and only on this one bucket. It lists individual S3 actions with no wildcards. | The Terraform tests check the trust policy, the account condition, the resources and the actions. |
| VPN sign-in | Users sign in with a client certificate. Only traffic for the VPC uses the tunnel. | The Terraform tests check the authorization rule. |
| VPN profile file | The file is written with owner-only permissions and is excluded from version control. | The Terraform tests check the permissions, and `.gitignore` excludes `*.ovpn`. |
| Secrets in the repository | State files, plans, variable files, keys, certificates, VPN profiles and workbooks are excluded from version control. | `.gitignore` was checked against every file in the project. |

## Weaknesses accepted for the proof of concept

These are acceptable for a short test with non-sensitive files. Each one must be fixed before real CUR data or real users are involved.

| Weakness | Risk | Production fix |
|---|---|---|
| Everyone shares one guest password. | Anyone with the password can read and change every file, and the logs cannot show who did what. | Join the gateway to a domain and give each user their own account. |
| The current guest password was shown in a terminal session transcript during testing. | Anyone who can read that transcript can open the share. | Run `terraform apply -replace=random_password.smb_guest` before anyone else uses the share. |
| Everyone shares one VPN client certificate. | Access cannot be removed from one person without replacing the certificate for everyone. No revocation list is set up. | Sign VPN users in with Microsoft Entra ID through SAML. |
| The Terraform state is a plain local file. | It contains the guest password and the private keys of the VPN certificate authority, server and client. | Store the state in an encrypted S3 bucket with versioning and locking, and limit who can read it. |
| The gateway has a public IP address, and port 445 is open to one public address. | The file-sharing port is reachable from the internet, although only from that address. | Move the gateway to a private subnet with no public address. |
| The gateway reaches S3 over the internet through an internet gateway. | Traffic is encrypted, but it leaves the AWS network. | Use VPC endpoints for S3 and Storage Gateway. |
| VPN connection logs, VPC flow logs, S3 server access logs and CloudTrail data events are off. | There is no record of who connected or which files were read. | Turn on Client VPN connection logs, VPC flow logs, and CloudTrail data events for the bucket. |
| S3 and EBS use AWS-managed keys. | Access to the data cannot be removed by disabling a key. | Use a customer managed AWS KMS key for the bucket and the disks. |
| The instance metadata service accepts version 1 requests. | Version 1 is easier to abuse if software on the instance is compromised. The gateway runs only AWS's own software, which lowers the risk. | Test the gateway with `http_tokens = "required"`, and require version 2 if the gateway still works. |
| The gateway's outbound security group rule allows all traffic. | A compromised gateway could connect anywhere. | Allow only HTTPS to the VPC endpoints, and the DNS, sign-in and time traffic that a domain-joined gateway exchanges with its domain controllers. |

## Where each secret lives

| Secret | Where it is stored | How to replace it |
|---|---|---|
| Guest password | Terraform state, and the gateway | `terraform apply -replace=random_password.smb_guest` |
| VPN certificate authority key | Terraform state | `terraform apply -replace=tls_private_key.vpn_ca`, then hand out the new profile file |
| VPN client key | Terraform state and the `.ovpn` profile file | `terraform apply -replace=tls_private_key.vpn_client`, then hand out the new profile file |
| AWS credentials | The AWS CLI's single sign-on cache on the computer that runs Terraform | They expire on their own. Sign in again with `aws sso login`. |

## Automated security checks

- **Terraform tests.** Thirteen plan-only tests in [`terraform/tests/security.tftest.hcl`](../terraform/tests/security.tftest.hcl) check the settings in the table above. They use mock providers, so they need no AWS account. All 13 passed. See [Test results](test-results.md).
- **Checkov.** The CI workflow scans the Terraform code with Checkov, an open-source scanner for insecure cloud settings. It reports findings without failing the build, because the weaknesses above are accepted on purpose. Checkov was not run on the computer used for this proof of concept, so this repository holds no Checkov results yet.

## Reporting a problem

See [SECURITY.md](../SECURITY.md).

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](../LICENSE) and the [disclaimers](../DISCLAIMER.md)._
