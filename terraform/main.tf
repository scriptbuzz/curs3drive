# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# AWS publishes the newest S3 File Gateway machine image under this public parameter.
data "aws_ssm_parameter" "gateway_ami" {
  name = "/aws/service/storagegateway/ami/FILE_S3/latest"
}

# Generated guest password, used when smb_guest_password is not set.
# Letters and digits only, so it can be typed into any sign-in prompt without escaping.
resource "random_password" "smb_guest" {
  length  = 24
  special = false
}

locals {
  az                 = data.aws_availability_zones.available.names[0]
  bucket_arn         = "arn:${data.aws_partition.current.partition}:s3:::${var.bucket_name}"
  smb_guest_password = coalesce(var.smb_guest_password, random_password.smb_guest.result)
}

# ============================================================
# Network: one VPC with one public subnet for the proof of concept
# ============================================================

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = var.name }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 0)
  availability_zone = local.az

  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "gateway" {
  name        = "${var.name}-gateway"
  description = "Allows the listed client PCs to reach the file share"
  vpc_id      = aws_vpc.this.id
}

# SMB file sharing from the listed client PCs only.
resource "aws_vpc_security_group_ingress_rule" "smb" {
  for_each = toset(var.allowed_client_cidrs)

  security_group_id = aws_security_group.gateway.id
  description       = "SMB file share access from an allowed client"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 445
  to_port           = 445
}

# HTTP from the machine running Terraform, needed once to activate the gateway.
resource "aws_vpc_security_group_ingress_rule" "activation" {
  for_each = toset(var.activation_cidrs)

  security_group_id = aws_security_group.gateway.id
  description       = "One-time gateway activation from the Terraform machine"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# The gateway calls AWS service endpoints and S3 over HTTPS.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.gateway.id
  description       = "Outbound access to AWS services"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ============================================================
# S3 bucket that holds the Excel files
# ============================================================

resource "aws_s3_bucket" "files" {
  count  = var.create_bucket ? 1 : 0
  bucket = var.bucket_name
}

resource "aws_s3_bucket_ownership_controls" "files" {
  count  = var.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.files[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "files" {
  count  = var.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.files[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "files" {
  count  = var.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.files[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning keeps the previous copy of a workbook after every save.
resource "aws_s3_bucket_versioning" "files" {
  count  = var.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.files[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Old copies are deleted after a set number of days so storage costs stay flat.
resource "aws_s3_bucket_lifecycle_configuration" "files" {
  count  = var.create_bucket ? 1 : 0
  bucket = aws_s3_bucket.files[0].id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.files]
}

# ============================================================
# IAM role the gateway uses to read and write the bucket
# ============================================================

data "aws_iam_policy_document" "gateway_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["storagegateway.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "gateway_s3" {
  name               = "${var.name}-s3-access"
  assume_role_policy = data.aws_iam_policy_document.gateway_assume.json
}

data "aws_iam_policy_document" "gateway_s3" {
  statement {
    sid = "Bucket"
    actions = [
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:ListBucketMultipartUploads",
    ]
    resources = [local.bucket_arn]
  }

  statement {
    sid = "Objects"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObject",
      "s3:GetObjectAcl",
      "s3:GetObjectVersion",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]
    resources = ["${local.bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "gateway_s3" {
  name   = "s3-access"
  role   = aws_iam_role.gateway_s3.id
  policy = data.aws_iam_policy_document.gateway_s3.json
}

# ============================================================
# Gateway machine on EC2
# ============================================================

resource "aws_instance" "gateway" {
  ami                    = nonsensitive(data.aws_ssm_parameter.gateway_ami.value)
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.gateway.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = 80
    encrypted   = true
  }

  tags = { Name = var.name }

  # The gateway updates its own software, so a newer published image must not replace a running gateway.
  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_ebs_volume" "cache" {
  availability_zone = local.az
  type              = "gp3"
  size              = var.cache_size_gib
  iops              = var.cache_iops
  throughput        = var.cache_throughput_mibps
  encrypted         = true

  tags = { Name = "${var.name}-cache" }
}

resource "aws_volume_attachment" "cache" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.cache.id
  instance_id = aws_instance.gateway.id
}

# A fixed public address, so the clients' saved drive mappings keep working.
resource "aws_eip" "gateway" {
  domain   = "vpc"
  instance = aws_instance.gateway.id

  tags = { Name = var.name }

  depends_on = [aws_internet_gateway.this]
}

# ============================================================
# Gateway activation, cache disk and file share
# ============================================================

resource "aws_storagegateway_gateway" "this" {
  gateway_name       = var.name
  gateway_type       = "FILE_S3"
  gateway_timezone   = var.gateway_timezone
  gateway_ip_address = aws_eip.gateway.public_ip

  smb_guest_password = local.smb_guest_password

  # Every connection must use SMB 3 encryption, because the proof of concept runs over the public internet.
  smb_security_strategy = "MandatoryEncryption"

  depends_on = [
    aws_volume_attachment.cache,
    aws_route_table_association.public,
    aws_vpc_security_group_ingress_rule.activation,
  ]
}

data "aws_storagegateway_local_disk" "cache" {
  gateway_arn = aws_storagegateway_gateway.this.arn
  disk_path   = var.cache_disk_path
}

resource "aws_storagegateway_cache" "this" {
  gateway_arn = aws_storagegateway_gateway.this.arn
  disk_id     = data.aws_storagegateway_local_disk.cache.disk_id
}

resource "aws_storagegateway_smb_file_share" "files" {
  gateway_arn     = aws_storagegateway_gateway.this.arn
  location_arn    = local.bucket_arn
  role_arn        = aws_iam_role.gateway_s3.arn
  file_share_name = var.file_share_name
  authentication  = "GuestAccess"

  default_storage_class = "S3_STANDARD"

  # Lets Windows lock a workbook so a second user gets Excel's read-only prompt.
  oplocks_enabled = true

  cache_attributes {
    cache_stale_timeout_in_seconds = var.cache_refresh_seconds
  }

  depends_on = [
    aws_storagegateway_cache.this,
    aws_iam_role_policy.gateway_s3,
    aws_s3_bucket_public_access_block.files,
  ]
}
