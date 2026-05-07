output "aws_region" {
  description = "Region where the proxy instance lives (for shell helpers)."
  value       = var.aws_region
}

output "ssh_user" {
  description = "SSH login user for the instance."
  value       = "ec2-user"
}

output "systemd_journal_unit" {
  description = "systemd unit name for journalctl -u (deepseek-proxy service)."
  value       = "deepseek-proxy"
}

output "public_ip" {
  description = "Elastic IP attached to the proxy (stable; sslip.io hostname uses this IP)."
  value       = aws_eip.proxy.public_ip
}

output "sslip_host" {
  description = "sslip.io hostname (Let's Encrypt / nginx server_name)."
  value       = "${replace(aws_eip.proxy.public_ip, ".", "-")}.sslip.io"
}

output "cursor_base_url_https" {
  description = "OpenAI-compatible base URL for Cursor (HTTPS via nginx after certbot)."
  value       = "https://${replace(aws_eip.proxy.public_ip, ".", "-")}.sslip.io/v1"
}

output "cursor_base_url_http" {
  description = "Same proxy over HTTP (port 80) if TLS not ready."
  value       = "http://${aws_eip.proxy.public_ip}/v1"
}

output "ssh_command" {
  description = "SSH as ec2-user (set key path)."
  value       = "ssh -i ~/.ssh/YOUR_KEY.pem ec2-user@${aws_eip.proxy.public_ip}"
}

output "instance_id" {
  value = aws_instance.proxy.id
}

output "security_group_id" {
  value = aws_security_group.proxy.id
}

output "certbot_junk_email" {
  description = "Junk ACME contact for certbot -m (export CERTBOT_EMAIL before deploy-ec2-https.sh)."
  value       = local.certbot_junk_email
}
