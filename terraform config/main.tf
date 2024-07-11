terraform {
  required_version = ">= 0.12"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}



# Step 1: Create VPC
resource "aws_vpc" "myvpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "MyTerraformVpc"
  }
}

# Step 2: Create Public Subnet
resource "aws_subnet" "PublicSubnet" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet"
  }
}

# Step 3: Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.myvpc.id
}

# Step 4: Create Route Table for Public Subnet
resource "aws_route_table" "PublicRT" {
  vpc_id = aws_vpc.myvpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Step 5: Create Security Group for EC2 Instance
resource "aws_security_group" "sg_ec2" {
  vpc_id      = aws_vpc.myvpc.id
  name        = "sg_ec2"
  description = "Security group for EC2 instances in VPC"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Step 6: Associate Route Table with Public Subnet
resource "aws_route_table_association" "PublicRTassociation" {
  subnet_id      = aws_subnet.PublicSubnet.id
  route_table_id = aws_route_table.PublicRT.id
}

# Step 7: Generate Private Key
resource "tls_private_key" "rsa_4096" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Step 7.2: Store Private Key Locally
resource "local_file" "private_key" {
  content  = tls_private_key.rsa_4096.private_key_pem
  filename = "terraform-key.pem"  
  provisioner "local-exec" {
    command = "chmod 400 terraform-key.pem"  # Secure the private key file
  }
}

# Step 8: Create Key Pair for SSH Access to EC2 Instance
resource "aws_key_pair" "key_pair" {
  key_name   = "terraform-key"
  public_key = tls_private_key.rsa_4096.public_key_openssh
}

# Step 9: Create EC2 Instance
resource "aws_instance" "my_instance" {
  ami                         = "ami-04a81a99f5ec58529"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.PublicSubnet.id
  key_name                    = aws_key_pair.key_pair.key_name
  vpc_security_group_ids      = [aws_security_group.sg_ec2.id]
  associate_public_ip_address = true
  tags = {
    Name = "MyEC2Instance"
  }

  provisioner "local-exec" {
    command = "touch inventory.ini"
  }

  provisioner "remote-exec" {
      inline = [
        "echo 'EC2 instance is ready.'"
      ]

      connection {
        type        = "ssh"
        host        = aws_instance.my_instance.public_ip
        user        = "ubuntu"
        private_key = tls_private_key.rsa_4096.private_key_pem
      }
  }
}

# Output Instance IP
output "instance_ip" {
  value = aws_instance.my_instance.public_ip
}

# Save the inventory file locally
resource "local_file" "inventory" {
  depends_on = [aws_instance.my_instance]

  filename = "${path.module}/inventory.ini"
  content = templatefile("${path.module}/inventory.tmpl", {
    instance_ip = aws_instance.my_instance.public_ip,
    key_path = "${path.module}/terraform-key.pem"
  })

  provisioner "local-exec" {
    command = "chmod 400 ${self.filename}"
  }
}

# Run Ansible Playbook
resource "null_resource" "run_ansible" {
  depends_on = [local_file.inventory]

  provisioner "local-exec" {
    command = "ansible-playbook -i inventory.ini docker-install.yml"
    working_dir = path.module
  }
}