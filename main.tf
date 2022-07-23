terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "4.21.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  ami                    = "ami-08d4ac5b634553e16" # Ubuntu Server 20.04 LTS
  instance_type          = "t2.micro"
  key_name               = "us-east-1-key"
  private_key_path       = "./us-east-1-key.pem"
}

resource "aws_instance" "web_server" {
  ami                    = local.ami
  instance_type          = local.instance_type
  key_name               = local.key_name
  vpc_security_group_ids = [aws_security_group.open_ports_22_80.id]
  iam_instance_profile   = "aws-ec2-container_registry-access" # instance role with access to ECR

  tags = {
    Name = "Web Server"
  }

# wait fot ssh available on remote host
  connection {
    type     = "ssh"
    user     = "ubuntu"
    private_key = file(local.private_key_path)
    host     = self.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "echo 'Build Server - SSH is UP!'",
    ]
  }
}

# Create security group
resource "aws_security_group" "open_ports_22_80" {
  name        = "allow_ports_22_and_80"
  description = "Allow inbound traffic on ports 22 and 80"

  ingress {
    description = "Open ssh port"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Open HTTP port"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ports_22_and_80"
  }
}

# Create a load balancer (classic)
resource "aws_elb" "web_elb" {
  name               = "web-server-elb"
  availability_zones = ["us-east-1a"]

# no https due to lack of domain certificate
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  instances                   = [aws_instance.web_server.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "web-server-elb"
  }
}

resource "local_file" "ansible_inventory" {
  content = templatefile("inventory.tmpl",
    {
     web_server_ip = aws_instance.web_server.public_ip,
    }
  )
  filename = "inventory"
}
