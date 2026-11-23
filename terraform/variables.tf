# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.

variable "name" {
  description = "Name used for the gateway and as a prefix for every AWS resource this configuration creates."
  type        = string
  default     = "cur-file-gateway"
}

variable "region" {
  description = "AWS Region for the gateway and the bucket. Pick the Region closest to the users."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile used to run Terraform. Leave null to use the default credentials."
  type        = string
  default     = null
}

# ---------- Who may connect ----------

variable "allowed_client_cidrs" {
  description = "Public IP ranges of the Mac and Windows PCs allowed to open the file share on TCP port 445, for example [\"203.0.113.10/32\"]."
  type        = list(string)

  validation {
    condition     = length(var.allowed_client_cidrs) > 0 && !contains(var.allowed_client_cidrs, "0.0.0.0/0")
    error_message = "List at least one client IP range, and never 0.0.0.0/0, because that would open the file share to the whole internet."
  }
}

variable "activation_cidrs" {
  description = "Public IP ranges of the machine that runs Terraform. Terraform needs TCP port 80 on the gateway once, to activate it. Set this to [] after the first successful apply."
  type        = list(string)
  default     = []
}

variable "smb_guest_password" {
  description = "Shared password for the file share's guest user, named smbguest. Leave it unset and Terraform generates a random 24-character password. If you set it, use 6 to 512 characters."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.smb_guest_password == null || can(regex("^.{6,512}$", var.smb_guest_password))
    error_message = "The guest password must be 6 to 512 characters long."
  }
}

# ---------- Network ----------

variable "vpc_cidr" {
  description = "Address range of the new VPC that holds the gateway."
  type        = string
  default     = "10.40.0.0/16"
}

variable "vpn_client_cidr" {
  description = "Address range handed out to computers connected through Client VPN. It must not overlap the VPC or the users' home and office networks, and must be between /12 and /22 in size."
  type        = string
  default     = "10.50.0.0/22"
}

variable "vpn_certificate_validity_hours" {
  description = "How long the VPN certificates stay valid, in hours. The default is two years."
  type        = number
  default     = 17520
}

# ---------- Gateway machine ----------

variable "instance_type" {
  description = "EC2 instance type for the gateway. AWS requires at least 4 vCPUs and 16 GB of memory. Use m5.2xlarge or larger for many users or multi-gigabyte workbooks."
  type        = string
  default     = "m5.xlarge"
}

variable "gateway_timezone" {
  description = "Time zone the gateway uses for its maintenance window, in the format GMT, GMT-5:00 or GMT+1:00."
  type        = string
  default     = "GMT-5:00"
}

variable "cache_size_gib" {
  description = "Size of the gateway's local cache disk in GiB. AWS requires at least 150 GiB. Make it larger than the set of files people open in a typical month."
  type        = number
  default     = 300

  validation {
    condition     = var.cache_size_gib >= 150
    error_message = "The cache disk must be at least 150 GiB."
  }
}

variable "cache_iops" {
  description = "Read and write operations per second for the gp3 cache disk."
  type        = number
  default     = 6000
}

variable "cache_throughput_mibps" {
  description = "Throughput of the gp3 cache disk in MiB per second. Large Excel files benefit from higher throughput."
  type        = number
  default     = 500
}

variable "cache_disk_path" {
  description = "Path under which the gateway reports the cache disk. On current EC2 instance types, the first extra disk is /dev/nvme1n1. Check it with: aws storagegateway list-local-disks --gateway-arn <gateway ARN>."
  type        = string
  default     = "/dev/nvme1n1"
}

# ---------- Bucket and file share ----------

variable "bucket_name" {
  description = "Name of the S3 bucket that holds the Excel files. It must be globally unique."
  type        = string
}

variable "create_bucket" {
  description = "Set to true to create the bucket with versioning and a cleanup rule. Set to false to use an existing bucket of that name."
  type        = bool
  default     = true
}

variable "noncurrent_version_days" {
  description = "Number of days S3 keeps an old version of a file after a newer one is saved. Applies only when this configuration creates the bucket."
  type        = number
  default     = 30
}

variable "file_share_name" {
  description = "Name of the file share that users connect to, for example cur in \\\\gateway-address\\cur."
  type        = string
  default     = "cur"
}

variable "cache_refresh_seconds" {
  description = "How often, in seconds, the gateway checks S3 for files added or changed outside the share, such as new CUR exports. The minimum is 300."
  type        = number
  default     = 300

  validation {
    condition     = var.cache_refresh_seconds >= 300 && var.cache_refresh_seconds <= 2592000
    error_message = "The refresh interval must be between 300 seconds and 30 days."
  }
}
