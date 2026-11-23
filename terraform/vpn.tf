# DRAFT - For internal use only. Proprietary and confidential. FPT owns this solution. See LICENSE.
# ============================================================
# AWS Client VPN, so users reach the file share over TCP port 443
# on networks that block the file-sharing port 445.
# ============================================================

# ---------- Certificates for VPN sign-in ----------
# Terraform creates a private certificate authority and signs one server
# certificate and one client certificate with it. The private keys are stored
# in the Terraform state, which is acceptable for this proof of concept only.

resource "tls_private_key" "vpn_ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "vpn_ca" {
  private_key_pem       = tls_private_key.vpn_ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = var.vpn_certificate_validity_hours

  subject {
    common_name  = "${var.name} VPN certificate authority"
    organization = var.name
  }

  allowed_uses = ["cert_signing", "crl_signing", "digital_signature"]
}

resource "tls_private_key" "vpn_server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "vpn_server" {
  private_key_pem = tls_private_key.vpn_server.private_key_pem
  dns_names       = [local.vpn_server_name]

  subject {
    common_name = local.vpn_server_name
  }
}

resource "tls_locally_signed_cert" "vpn_server" {
  cert_request_pem      = tls_cert_request.vpn_server.cert_request_pem
  ca_private_key_pem    = tls_private_key.vpn_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.vpn_ca.cert_pem
  validity_period_hours = var.vpn_certificate_validity_hours

  allowed_uses = ["digital_signature", "key_encipherment", "server_auth"]
}

resource "tls_private_key" "vpn_client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "vpn_client" {
  private_key_pem = tls_private_key.vpn_client.private_key_pem

  subject {
    common_name = local.vpn_client_name
  }
}

resource "tls_locally_signed_cert" "vpn_client" {
  cert_request_pem      = tls_cert_request.vpn_client.cert_request_pem
  ca_private_key_pem    = tls_private_key.vpn_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.vpn_ca.cert_pem
  validity_period_hours = var.vpn_certificate_validity_hours

  allowed_uses = ["digital_signature", "key_encipherment", "client_auth"]
}

# Client VPN reads the server certificate from AWS Certificate Manager.
# Because the same authority signed the client certificate, the endpoint also
# uses this certificate's chain to check the clients.
resource "aws_acm_certificate" "vpn_server" {
  private_key       = tls_private_key.vpn_server.private_key_pem
  certificate_body  = tls_locally_signed_cert.vpn_server.cert_pem
  certificate_chain = tls_self_signed_cert.vpn_ca.cert_pem

  tags = { Name = "${var.name}-vpn-server" }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------- VPN endpoint ----------

resource "aws_security_group" "vpn" {
  name        = "${var.name}-vpn"
  description = "Attached to the Client VPN endpoint inside the VPC"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_egress_rule" "vpn_all" {
  security_group_id = aws_security_group.vpn.id
  description       = "VPN users may reach anything inside the VPC"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
}

# The gateway accepts file-sharing connections from VPN users.
resource "aws_vpc_security_group_ingress_rule" "smb_from_vpn" {
  security_group_id            = aws_security_group.gateway.id
  description                  = "SMB file share access from Client VPN users"
  referenced_security_group_id = aws_security_group.vpn.id
  ip_protocol                  = "tcp"
  from_port                    = 445
  to_port                      = 445
}

resource "aws_ec2_client_vpn_endpoint" "this" {
  description            = "${var.name} access to the file share"
  server_certificate_arn = aws_acm_certificate.vpn_server.arn
  client_cidr_block      = var.vpn_client_cidr
  vpc_id                 = aws_vpc.this.id
  security_group_ids     = [aws_security_group.vpn.id]

  # TCP on port 443 passes through networks that allow only web traffic.
  transport_protocol = "tcp"
  vpn_port           = 443

  # Only traffic for the VPC uses the VPN. Other internet traffic is unchanged.
  split_tunnel = true

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = aws_acm_certificate.vpn_server.arn
  }

  connection_log_options {
    enabled = false
  }

  tags = { Name = var.name }
}

resource "aws_ec2_client_vpn_network_association" "this" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  subnet_id              = aws_subnet.public.id
}

resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = var.vpc_cidr
  authorize_all_groups   = true
  description            = "All VPN users may reach the VPC"
}

# ---------- Profile file for the AWS VPN Client app ----------

locals {
  vpn_server_name = "vpn-server.${var.name}.internal"
  vpn_client_name = "vpn-client.${var.name}.internal"

  vpn_profile = <<-EOT
    client
    dev tun
    proto tcp
    remote ${trimprefix(aws_ec2_client_vpn_endpoint.this.dns_name, "*.")} 443
    remote-random-hostname
    resolv-retry infinite
    nobind
    remote-cert-tls server
    cipher AES-256-GCM
    verb 3
    reneg-sec 0
    <ca>
    ${trimspace(tls_self_signed_cert.vpn_ca.cert_pem)}
    </ca>
    <cert>
    ${trimspace(tls_locally_signed_cert.vpn_client.cert_pem)}
    </cert>
    <key>
    ${trimspace(tls_private_key.vpn_client.private_key_pem)}
    </key>
  EOT
}

# Written next to this configuration with owner-only permissions.
# The file holds a private key, and .gitignore keeps it out of version control.
resource "local_sensitive_file" "vpn_profile" {
  filename        = "${path.module}/${var.name}.ovpn"
  content         = local.vpn_profile
  file_permission = "0600"
}
