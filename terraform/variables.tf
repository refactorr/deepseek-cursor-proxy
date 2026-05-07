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

variable "allowed_ssh_cidr" {
  type        = string
  description = "CIDR allowed for SSH (port 22). Tighten in production."
  default     = "0.0.0.0/0"
}

variable "allowed_http_cidr" {
  type        = string
  description = "CIDR allowed for HTTP/HTTPS (80/443) to nginx."
  default     = "0.0.0.0/0"
}
