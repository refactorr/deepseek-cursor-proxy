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
  description = "EC2 instance type (more RAM/CPU for heavy proxy + uv workloads)."
  default     = "t3.medium"
}

variable "key_name" {
  type        = string
  description = "Existing EC2 key pair name for SSH (create in console or `aws ec2 create-key-pair`)."
}

variable "root_volume_gb" {
  type        = number
  description = "Root gp3 volume size (GiB)."
  default     = 50
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
