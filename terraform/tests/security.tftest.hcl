# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.
# Plan-only tests that check the security settings of the configuration.
# They use mock providers, so they need no AWS account and create nothing.
# Run them in the terraform folder with: terraform test

mock_provider "aws" {
  override_data {
    target = data.aws_availability_zones.available
    values = { names = ["us-east-1a", "us-east-1b"] }
  }

  override_data {
    target = data.aws_ssm_parameter.gateway_ami
    values = { value = "ami-0123456789abcdef0" }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "111122223333" }
  }

  override_data {
    target = data.aws_partition.current
    values = { partition = "aws" }
  }

  override_data {
    target = data.aws_iam_policy_document.gateway_assume
    values = { json = "{}" }
  }

  override_data {
    target = data.aws_iam_policy_document.gateway_s3
    values = { json = "{}" }
  }
}

mock_provider "local" {}

variables {
  bucket_name          = "example-cur-bucket"
  allowed_client_cidrs = ["203.0.113.10/32"]
}

run "file_share_requires_smb_encryption" {
  command = plan

  assert {
    condition     = aws_storagegateway_gateway.this.smb_security_strategy == "MandatoryEncryption"
    error_message = "Every SMB connection to the gateway must be encrypted."
  }
}

run "smb_port_open_only_to_listed_addresses" {
  command = plan

  assert {
    condition     = alltrue([for rule in aws_vpc_security_group_ingress_rule.smb : rule.from_port == 445 && rule.to_port == 445 && contains(var.allowed_client_cidrs, rule.cidr_ipv4)])
    error_message = "The public SMB rule must open only port 445, and only to the listed client addresses."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.smb) == length(var.allowed_client_cidrs)
    error_message = "There must be exactly one SMB rule per listed client address."
  }
}

run "activation_port_closed_by_default" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.activation) == 0
    error_message = "Port 80 must stay closed unless activation addresses are listed."
  }
}

run "open_internet_is_rejected" {
  command = plan

  variables {
    allowed_client_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.allowed_client_cidrs]
}

run "short_guest_password_is_rejected" {
  command = plan

  variables {
    smb_guest_password = "abc"
  }

  expect_failures = [var.smb_guest_password]
}

run "cache_smaller_than_aws_minimum_is_rejected" {
  command = plan

  variables {
    cache_size_gib = 100
  }

  expect_failures = [var.cache_size_gib]
}

run "disks_are_encrypted" {
  command = plan

  assert {
    condition     = aws_ebs_volume.cache.encrypted
    error_message = "The cache disk must be encrypted."
  }

  assert {
    condition     = aws_instance.gateway.root_block_device[0].encrypted
    error_message = "The gateway's system disk must be encrypted."
  }
}

run "bucket_is_private_encrypted_and_versioned" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.files[0].block_public_acls,
      aws_s3_bucket_public_access_block.files[0].block_public_policy,
      aws_s3_bucket_public_access_block.files[0].ignore_public_acls,
      aws_s3_bucket_public_access_block.files[0].restrict_public_buckets,
    ])
    error_message = "All four S3 public access blocks must be on."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.files[0].rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "The bucket must encrypt new objects by default."
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.files[0].versioning_configuration).status == "Enabled"
    error_message = "Versioning must be on, so an earlier copy survives a bad save."
  }

  assert {
    condition     = one(aws_s3_bucket_ownership_controls.files[0].rule).object_ownership == "BucketOwnerEnforced"
    error_message = "Object ACLs must be disabled."
  }
}

run "existing_bucket_is_left_alone" {
  command = plan

  variables {
    create_bucket = false
  }

  assert {
    condition     = length(aws_s3_bucket.files) == 0 && length(aws_s3_bucket_versioning.files) == 0
    error_message = "With create_bucket = false, Terraform must not create or change a bucket."
  }
}

run "gateway_role_is_limited_to_one_bucket" {
  command = plan

  assert {
    condition     = length(data.aws_iam_policy_document.gateway_assume.statement) == 1 && length(data.aws_iam_policy_document.gateway_s3.statement) == 2
    error_message = "The trust policy must have one statement and the S3 policy two, so the checks below are not empty."
  }

  assert {
    condition = alltrue([
      for statement in data.aws_iam_policy_document.gateway_assume.statement :
      alltrue([for principal in statement.principals : toset(principal.identifiers) == toset(["storagegateway.amazonaws.com"])])
    ])
    error_message = "Only the Storage Gateway service may use the gateway's role."
  }

  assert {
    condition = alltrue([
      for statement in data.aws_iam_policy_document.gateway_assume.statement :
      anytrue([for c in statement.condition : c.variable == "aws:SourceAccount" && toset(c.values) == toset(["111122223333"])])
    ])
    error_message = "The role must accept requests only on behalf of this AWS account."
  }

  assert {
    condition = alltrue(flatten([
      for statement in data.aws_iam_policy_document.gateway_s3.statement :
      [for r in statement.resources : r == "arn:aws:s3:::example-cur-bucket" || r == "arn:aws:s3:::example-cur-bucket/*"]
    ]))
    error_message = "The gateway's S3 permissions must cover only the file share's bucket."
  }

  assert {
    condition = alltrue(flatten([
      for statement in data.aws_iam_policy_document.gateway_s3.statement :
      [for a in statement.actions : startswith(a, "s3:") && !strcontains(a, "*")]
    ]))
    error_message = "The gateway's permissions must list individual S3 actions, with no wildcards."
  }
}

run "file_share_uses_locking_and_refresh" {
  command = plan

  assert {
    condition     = aws_storagegateway_smb_file_share.files.oplocks_enabled
    error_message = "Opportunistic locks must be on, so Excel can tell when someone else has a workbook open."
  }

  assert {
    condition     = one(aws_storagegateway_smb_file_share.files.cache_attributes).cache_stale_timeout_in_seconds == 300
    error_message = "The share must check S3 for new files every 5 minutes by default."
  }
}

run "vpn_uses_tcp_443_and_split_tunnel" {
  command = plan

  assert {
    condition     = aws_ec2_client_vpn_endpoint.this.transport_protocol == "tcp" && aws_ec2_client_vpn_endpoint.this.vpn_port == 443
    error_message = "The VPN must use TCP port 443, so it passes through networks that allow only web traffic."
  }

  assert {
    condition     = aws_ec2_client_vpn_endpoint.this.split_tunnel
    error_message = "Only traffic for the VPC may use the VPN."
  }

  assert {
    condition     = aws_ec2_client_vpn_authorization_rule.vpc.target_network_cidr == var.vpc_cidr
    error_message = "VPN users may reach only the VPC."
  }
}

run "vpn_profile_file_is_private" {
  command = plan

  assert {
    condition     = local_sensitive_file.vpn_profile.file_permission == "0600"
    error_message = "The VPN profile file holds a private key and must be readable only by its owner."
  }
}
