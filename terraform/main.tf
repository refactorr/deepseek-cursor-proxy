data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_default_subnet" "this" {
  availability_zone = "${var.aws_region}a"
}

resource "aws_security_group" "proxy" {
  name        = "${var.instance_name}-sg"
  description = "SSH + HTTP/HTTPS for deepseek-cursor-proxy (nginx TLS)"

  vpc_id = aws_default_subnet.this.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "HTTP (certbot / redirect)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_http_cidr]
  }

  ingress {
    description = "HTTPS (Cursor -> nginx -> proxy)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_http_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.instance_name}-sg"
  }
}

resource "aws_instance" "proxy" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_default_subnet.this.id
  vpc_security_group_ids = [aws_security_group.proxy.id]

  user_data = file("${path.module}/user-data.sh")

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = var.instance_name
  }
}

resource "aws_eip" "proxy" {
  domain = "vpc"
  tags = {
    Name = "${var.instance_name}-eip"
  }
}

resource "aws_eip_association" "proxy" {
  instance_id   = aws_instance.proxy.id
  allocation_id = aws_eip.proxy.id
}
