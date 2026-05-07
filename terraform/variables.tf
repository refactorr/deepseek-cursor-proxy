variable "aws_region" {
  type        = string
  description = "AWS region for the proxy instance."
  default     = "us-east-1"
}

variable "instance_name" {
  type        = string
  description = "EC2 Name tag (used by deploy script discovery if no terraform output)."
  default     = "deepseek-cursor-proxy"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type."
  default     = "t3.small"
}

variable "key_name" {
  type        = string
  description = "Existing EC2 key pair name for SSH (create in console or `aws ec2 create-key-pair`)."
}

variable "root_volume_gb" {
  type        = number
  description = "Root gp3 volume size (GiB)."
  default     = 30
}

variable "allowed_proxy_cidr" {
  type        = string
  description = "Only this CIDR may reach nginx on :80 and :443 (your public IPv4/32, e.g. from curl -4 ifconfig.me)."
  nullable    = false

  validation {
    condition     = !contains(["0.0.0.0/0", "::/0"], var.allowed_proxy_cidr)
    error_message = "allowed_proxy_cidr must not be open internet; use your public IP/32 (e.g. 203.0.113.7/32)."
  }
}

variable "allowed_ssh_cidr" {
  type        = string
  default     = null
  description = "CIDR for SSH :22. Defaults to allowed_proxy_cidr when null (same machine admin + Cursor)."
  nullable    = true
}

variable "certbot_junk_domain" {
  type        = string
  description = "Domain for junk Let's Encrypt / certbot -m contact (no mailbox created here)."
  default     = "daggrai.com"
}

variable "certbot_junk_local_part" {
  type        = string
  description = "Local part of junk ACME contact email (before @)."
  default     = "acme-le-junk"
}
