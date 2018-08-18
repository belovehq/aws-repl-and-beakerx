# Variables specification; values set in terraform.tfvars

variable "region" {
  type = "string"
  description = "AWS region"
}

variable availability_zone {
  type = "string"
  description = "availability zone for instance(s) and EBS volume (s)"
}

variable "profile" {
  type = "string"
  description = "AWS profile as per ~/.aws/credentials"
}

variable ec2_iam_role {
  type = "string"
  description = "The IAM Role associated with the instance"
}

variable ec2_security_groups {
  type = "list"
  description = "The security groups (i.e. firewall rules) attached to the instance"
}

variable ec2_key_name {
  type = "string"
  description = "Key pair (among key pairs defined in the EC2 dashboard) to use for ssh access"
}

variable ssh_port {
  type = "string"
  description = "ssh port, compatible with firewall rules of ec2_security_groups"
}

variable ssh_private_key_path {
  type = "string"
  description = "Path to the local copy (.pem file) of the private key of ec2_key_name"
}


# AWS Provider

provider "aws" {
  profile = "${var.profile}"
  region = "${var.region}"
}

# locate AMI

data "aws_ami" "clojure-repl-beakerx" {
  most_recent = true
  owners = [
    "self"]
  filter {
    name = "name"
    values = [
      "clojure-repl-and-beakerx-*"]
  }
}

# locate EBS volume

data "aws_ebs_volume" "clojure" {
  most_recent = true
  filter {
    name = "tag:Name"
    values = [
      "clojure-repl-beakerx"]
  }
}

# Instance definition
resource "aws_instance" "clojure" {

  instance_type = "t2.micro"
  monitoring = true
  tags {
    Name = "clojure-repl-beakerx"
  }
  credit_specification {
    cpu_credits = "unlimited"
  }
  root_block_device {
    volume_size = 8
  }
  availability_zone = "${var.availability_zone}"
  ami = "${data.aws_ami.clojure-repl-beakerx.id}"
  key_name = "${var.ec2_key_name}"
  iam_instance_profile = "${var.ec2_iam_role}"
  security_groups = "${var.ec2_security_groups}"
  user_data = "#!/bin/bash\nsed -i 's/#Port 22/Port ${var.ssh_port}/g' /etc/ssh/sshd_config && service sshd restart"
}

# EBS volume attachment including mount/unmount
resource "aws_volume_attachment" "clojure" {
  device_name = "/dev/sdd"
  volume_id = "${data.aws_ebs_volume.clojure.id}"
  instance_id = "${aws_instance.clojure.id}"
  connection {
    type = "ssh"
    user = "ec2-user"
    host = "${aws_instance.clojure.public_dns}"
    port = "${var.ssh_port}"
    private_key = "${file(var.ssh_private_key_path)}"
  }
  provisioner "remote-exec" {
    script = "scripts/ebs-mount"
  }
  provisioner "remote-exec" {
    when = "destroy"
    script = "scripts/ebs-unmount"
  }
}
