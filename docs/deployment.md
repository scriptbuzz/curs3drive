# Deployment Guide

_DRAFT - For internal use only. Last modified: 2026-11-23 11:37 EST by mbitar._

This guide deploys the proof of concept into an AWS account with Terraform. The steps are the same on macOS and Windows, because Terraform and the AWS CLI run on both. A first deployment takes about 25 minutes, most of it spent waiting for AWS.

[Back to the README](../README.md)

## What gets created

| Part | What it does |
|---|---|
| VPC with one public subnet | Holds the gateway and the VPN endpoint, separate from every existing network. |
| S3 File Gateway on an m5.xlarge EC2 instance | Presents the S3 bucket as a Windows file share over SMB, the protocol Windows uses for network drives. |
| 300 GiB gp3 EBS cache disk | Keeps recently used files on fast local storage, so they open without a download from S3. |
| Elastic IP address | Gives the gateway a fixed public address. Terraform needs it once to activate the gateway. |
| S3 bucket | Holds the Excel files. Versioning keeps the previous copy after every save, and a lifecycle rule deletes old copies after 30 days. |
| IAM role | Lets the gateway read and write that one bucket and nothing else. |
| AWS Client VPN endpoint | Carries file-sharing traffic over TCP port 443 for networks that block port 445. |
| VPN certificates and profile file | Let the AWS VPN Client app sign in to the VPN. Terraform creates a private certificate authority, a server certificate in AWS Certificate Manager, and one client certificate. |
| File share named `cur` | The share users connect to. It uses one shared guest password and requires SMB encryption. |

The [architecture page](architecture.md) explains how these parts work together.

## Before you start

1. Install the AWS CLI version 2 and Terraform 1.7 or newer. Version 1.7 is the first that runs the configuration's tests.
2. Sign in with an AWS profile that may create VPC, EC2, S3, IAM, ACM, Client VPN and Storage Gateway resources:
   ```bash
   aws sso login --profile sandbox01
   ```
3. Find the public IP address of the computer that runs Terraform by opening https://checkip.amazonaws.com on it. Terraform contacts the gateway from this address once, to activate it.
4. Decide how users will reach the share. If their network allows outbound TCP port 445, they can connect straight to the gateway's public address. If it does not, they use the Client VPN. The [troubleshooting page](troubleshooting.md#a-port-test-succeeds-but-the-share-does-not-answer) shows how to tell, because some routers fake a successful port test.

## Deploy

1. In the `terraform` folder, copy `terraform.tfvars.example` to `terraform.tfvars`.
2. In `terraform.tfvars`, set these values:

   | Setting | What to enter |
   |---|---|
   | `region` | The AWS Region closest to the users. |
   | `aws_profile` | The profile you signed in with. |
   | `bucket_name` | A globally unique name for the new bucket. |
   | `allowed_client_cidrs` | The public address of each computer allowed to reach port 445 directly, ending in `/32`, which means exactly one address. |
   | `activation_cidrs` | The public address of the computer running Terraform, ending in `/32`. |

3. Download the providers and save a plan:
   ```bash
   terraform init
   ```
   ```bash
   terraform plan -out=poc.tfplan
   ```
   Read the plan. A first deployment adds 41 resources and changes or deletes nothing.
4. Apply the plan:
   ```bash
   terraform apply poc.tfplan
   ```
   Terraform starts the gateway, activates it over port 80, adds the cache disk, creates the file share, and then creates the VPN endpoint. Attaching the VPN endpoint to the subnet alone takes about 10 minutes.
5. Close port 80, which only activation needed. Set `activation_cidrs = []` in `terraform.tfvars` and apply again:
   ```bash
   terraform apply
   ```
   The plan shows one security group rule to delete.

## After the deployment

Show the values users need:

```bash
terraform output
```

| Output | Who needs it |
|---|---|
| `gateway_private_ip` | Everyone who connects through the VPN. |
| `gateway_id` | Windows users. It forms the first part of the guest user name. |
| `vpn_profile_file` | Everyone who connects through the VPN. Hand the file over privately, because it holds a private key. |
| `mac_connect_address_vpn` | Mac users. |
| `windows_map_command_vpn` | Windows users. |

Show the guest password, and hand it over through a password manager:

```bash
terraform output -raw smb_guest_password
```

Terraform generated this password, and it is stored in the Terraform state. To replace it with a new one, run:

```bash
terraform apply -replace=random_password.smb_guest
```

Then follow [Connect from Windows 11](connect-windows.md) or [Connect from macOS](connect-macos.md).

## If the cache disk is not found

Terraform may stop during the first apply with an error that the local disk was not found. That means the gateway reports the cache disk under a different path than `/dev/nvme1n1`. List the paths it reports:

```bash
aws storagegateway list-local-disks --gateway-arn "$(terraform state show -no-color aws_storagegateway_gateway.this | awk '/^ *arn /{print $3}' | tr -d '"')"
```

Copy the `DiskPath` of the disk with the size you chose into `cache_disk_path` in `terraform.tfvars`, and run `terraform apply` again. In this project's deployment, `/dev/nvme1n1` was correct.

## Remove the deployment

Run the [test plan](test-plan.md) first if you still need results from this deployment. Then preview what will be deleted:

```bash
terraform plan -destroy
```

Terraform cannot delete a bucket that still contains files, including old versions. Choose one of these before destroying:

- **Keep the bucket and its files.** Tell Terraform to forget the bucket and its settings, so that `terraform destroy` leaves them in place:
  ```bash
  terraform state rm 'aws_s3_bucket.files[0]' 'aws_s3_bucket_versioning.files[0]' 'aws_s3_bucket_lifecycle_configuration.files[0]' 'aws_s3_bucket_public_access_block.files[0]' 'aws_s3_bucket_server_side_encryption_configuration.files[0]' 'aws_s3_bucket_ownership_controls.files[0]'
  ```
  Then run `terraform destroy`. Do not set `create_bucket = false` for this purpose, because Terraform would then try to delete the bucket.
- **Delete the files too.** Empty the bucket, including all versions, in the S3 console, and then run `terraform destroy`.

Delete the VPN profile file and the AWS VPN Client profile from every computer afterwards, because the certificates stay valid for two years even though nothing accepts them any more. If nobody needs the VPN app for anything else, uninstall it. On a Mac that installed it with Homebrew, run:

```bash
brew uninstall --cask aws-vpn-client
```

This project's own deployment was removed on 23 November 2026 with the second option, so the bucket and all its files were deleted. The [test results](test-results.md#removal) record the checks that followed.

---

_DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See the [license](../LICENSE) and the [disclaimers](../DISCLAIMER.md)._
