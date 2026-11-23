# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.

output "gateway_public_ip" {
  description = "Public IP address of the gateway."
  value       = aws_eip.gateway.public_ip
}

output "gateway_id" {
  description = "ID of the gateway. Windows uses it as the domain part of the guest user name."
  value       = aws_storagegateway_gateway.this.gateway_id
}

output "bucket_name" {
  description = "S3 bucket behind the file share."
  value       = var.bucket_name
}

output "smb_guest_password" {
  description = "Guest password for the file share. Show it with: terraform output -raw smb_guest_password"
  value       = local.smb_guest_password
  sensitive   = true
}

output "mac_connect_address" {
  description = "Address to enter in Finder under Go > Connect to Server."
  value       = "smb://smbguest@${aws_eip.gateway.public_ip}/${var.file_share_name}"
}

output "windows_map_command" {
  description = "Command that maps the file share as drive S: on Windows over the public internet. It asks for the guest password."
  value       = "net use S: \\\\${aws_eip.gateway.public_ip}\\${var.file_share_name} /user:${aws_storagegateway_gateway.this.gateway_id}\\smbguest /persistent:yes"
}

output "gateway_private_ip" {
  description = "Private IP address of the gateway, reachable while the VPN is connected."
  value       = aws_instance.gateway.private_ip
}

output "vpn_profile_file" {
  description = "Profile file to import into the AWS VPN Client app."
  value       = abspath(local_sensitive_file.vpn_profile.filename)
}

output "mac_connect_address_vpn" {
  description = "Address to enter in Finder under Go > Connect to Server while the VPN is connected."
  value       = "smb://smbguest@${aws_instance.gateway.private_ip}/${var.file_share_name}"
}

output "windows_map_command_vpn" {
  description = "Command that maps the file share as drive S: on Windows while the VPN is connected. It asks for the guest password."
  value       = "net use S: \\\\${aws_instance.gateway.private_ip}\\${var.file_share_name} /user:${aws_storagegateway_gateway.this.gateway_id}\\smbguest /persistent:yes"
}
