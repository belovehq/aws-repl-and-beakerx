# Variables specification; set the values in terraform.tfvars

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


# AWS Provider

provider "aws" {
  profile = "${var.profile}"
  region = "${var.region}"
}


resource "aws_ebs_volume" "clojure-repl-beakerx" {
  type = "standard"
  size = 500
  tags {
    Name = "clojure-repl-beakerx"
  }
  availability_zone = "${var.availability_zone}"
}

