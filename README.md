# Leiningen REPL and BeakerX notebooks on Amazon EC2

This repo uses the  [Packer](https://www.packer.io) + 
[Terraform](https://www.terraform.io) combo to deploy 
an interactive Clojure development machine with [Leiningen](https://leiningen.org/) 
and [BeakerX](http://beakerx.com/)
on Amazon EC2. This allows coding on a local machine while executing code
directly on the AWS infrastructure with easy access to resources 
such as S3, EMR, Elasticsearch, etc.

The deployment involves 3 simple steps/layers:
 
* provisioning an Amazon Machine Image (Packer)   

* creating a reusable EBS volume for data (Terraform)

* creating an EC2 instance based on the above AMI 
  and mounting the EBS volume onto it at `/data` (Terraform). 

This project showcases the declarative and immutable paradigm of 
Packer and Terraform:

* Declarative: we describe the resources we wish to create rather 
than the steps taken to build them or amend them, 

* Immutable: we destroy old resources and create new resources 
when we want to deploy changes, rather than amending existing resources. 


## Installation

1. Download this repo and install [Packer](https://www.packer.io/downloads.html)
and [Terraform](https://www.terraform.io/downloads.html) on your local machine.

2. If you don't already have one, set up an 
   [AWS account](https://aws.amazon.com/free).
    
3. Create IAM Profile(s) to allow Packer and Terraform to manage resources. 
   Register this/these profiles in your local `~/.aws/credentials` file, 
    and set the environment variable `AWS_INSTANCE` to the name of the profile 
    that Packer should use. Examples of (broad) permissions are:
   
   * Packer:  `AmazonEC2ContainerRegistryFullAccess`
    
   * Terraform: `AmazonEC2FullAccess` + an inline policy with the `IAMPassRole`.   
  
4. Still in IAM, create an IAM role for the instance, with access to the AWS
   services that you'll wish to access via the instance.
   
5. In EC2, create the following resources so that Terraform  can ssh 
   onto the instance: 
   
   * A key pair, which the ssh server on the instance will use to 
   authenticate connections; download the private key onto your local 
   machine (`.pem` file). 
    
   * A security group (firewall rules) that provides inbound TCP access 
   to a port of your choosing for ssh access. 
  
## Usage

### Step 1: Burning the AMI with Packer

Edit the variables in `packer/images.json` to match your AWS region
and the ID of the latest 'minimal' Amazon Linux 2 AMI in that region 
(AMIs named `amzn2-ami-minimal-hvm-*`). Leave the `aws_profile` line unchanged
in order to use the IAM profile you've set up earlier on.

```json 
  "variables": {
    "aws_profile": "{{env `AWS_PROFILE`}}",
    "region": "eu-west-1",
    "ami": "ami-586867b2"
  }
  ```  

Edit the dependencies in `packer/files/.packer/project.clj` to
amend the list of pre-loaded Clojure libraries. 

In the `packer` directory, run `packer build image.json`. This will 
create the new image and install Leiningen, BeakerX and libraries. The image
will then be ready in the EC2 image registry. 

### Step 2: EBS volume with Terraform

In the `terraform/ebs` directory, create a new `terraform.tfvars` 
file from the example file. Edit the variables to match your region 
and IAM profile for Terraform. 

```hcl-terraform
region = "eu-west-1"
availability_zone = "eu-west-1a"
profile = "terraform"
```
You can also edit `main.tf` to change volume size and type. 

In the `terraform/ebs` directory, run `terraform init` and then `terraform apply`
to create the EBS volume.

### Step 3: EC2 instance with Terraform

In the `terraform/ec2` directory, create a  new `terraform.tfvars` 
file from the example file. Edit the variables to match your region, 
IAM profile for Terraform, key name, instance IAM role, security group and 
ssh connection parameters. 

```hcl-terraform
region = "eu-west-1"
availability_zone = "eu-west-1c"
profile = "terraform"
ec2_iam_role = "my-iam-role"
ec2_key_name = "my-ec2-key"
ssh_private_key_path = "/my-private-keys/my-ec2-key.pem"
ec2_security_groups = ["my-security-group"]
ssh_port = "12345"
```
You can also edit `main.tf` to change instance type, root disk size... 

In the `terraform/ec2` directory, run `terraform init` and then `terraform apply`.
This creates the instance and mounts the EBS volume to it at `/data`.

### Using the instance

Ssh into the instance using the port and private key (`.pem` file)
that you've set up earlier. 
Instruct ssh to forward some ports from your local machine to the instance
in order to locally access the remote nREPL and Jupyter notebooks. 
For example:

```bash
ssh -i "/my-private-keys/my-ec2-key.pem" \ 
    -p 12345 \ 
    -L 20000:localhost:20000 \
    -L 20001:localhost:20001 \
    ec2-user@ec2-444-333-222-111.eu-west-1.compute.amazonaws.com
```

You may then, via shh:

* Start a Clojure nREPL on one of the remote forwarding ports e.g. `lein :start :port 20000`. 
  Connect your local development environment to it via the matching local port. 
  If started from the home directory `~`, the REPL will use the minimal 
  `project.clj` file that is pre-installed there: it will run Clojure 1.9 with the 
  `alembic` library, which allows dynamically loading dependencies from the REPL. 
  Use the `/data` directory to persist new projects and files on the reusable EBS 
  volume.   
  
* Start Jupyter/BeakerX on one of the remote forwarding ports
  e.g. `jupyter notebook --port=20001`. In your local browser, open the authentication
  URL produced by Jupyter (change the port to the matching local port
  if different). If you start Jupyter from the `/data` directory, you will be be able 
  to save notebooks on the reusable EBS volume.
  
### Loading Clojure libraries

The Packer template pre-populates the local Maven repository `~/.m2` 
with selected libraries as per `packer/files/.packer/project.clj`. Leiningen
will have access to these and will, as usual, download new libraries directly
from Clojars or Maven Central into `~/.m2` if they're not already there. 

BeakerX uses its own local Maven repository rather than `~/.m2`, out of concern that `~/.m2`
[is not entirely safe for concurrent access](http://nbviewer.jupyter.org/github/twosigma/beakerx/blob/master/doc/groovy/ClasspathMagicCommands.ipynb).
You can still instruct BeakerX to use `~/.m2` instead of its own repo,
so that it can access the pre-loaded libraries. 
To do so, run `%classpath config resolver mvnLocal` in your Beaker notebook. 
The `%classpath add mvn` directive will then load libraries from `~/.m2`.  

Another reason for switching the BeakerX repo to `~/.m2` is that
BeakerX can only download dependencies from Maven Central, but not from Clojars. 
So if you want to use a new Clojars library  in BeakerX, 
download it first into `~/.m2` with Leiningen 
(with Alembic or by running `lein deps` over a `project.clj`) and then
load it in BeakerX with `%classpath config resolver mvnLocal` and `%classpath add mvn`. 
 
Because the local Maven repository `~/.m2` is located on the instance's 
transient root drive, it will be reset to its AMI state when the instance is 
destroyed/recreated with Terraform. So if you use a library frequently, 
burn it into the AMI with Packer via `packer/files/.packer/project.clj`.
 
 
## Redeploying the configuration 

A few tasks will take place regularly after the initial deployment, such as destroying and recreating 
the instance, rolling out a new AMI, or destroying and recreating the whole stack.

In Terraform's immutable logic, we destroy and recreate 
resources rather than amending/mutating them. To do this painlessly, this project follows 
[Terraform's guidelines](https://www.terraform.io/docs/commands/plan.html#resource-targeting)
about breaking an overall configuration into several smaller configurations, and using 
[data sources](https://www.terraform.io/docs/configuration/data-sources.html)
when a configuration needs to access access resources created by another configuration. 
In our case, the `terraform/ec2` configuration uses data sources to locate the AMI 
and the EBS volume created by the `terraform/ebs` configuration.  


### Recreating the EC2 instance 

In the `terraform/ec2` directory,  run `terraform destroy`. Amend
the Terraform configuration file if needed. Later, recreate the instance with 
`terraform apply`. This will create a new EC2 instance and attach it to the 
same EBS volume as before, which remains intact.

Destroying and recreating the EC2 instance is preferred to stopping and restarting it. 
Restarting the instance would indeed occasion a change of IP address
and hence a configuration drift between EC2 and Terraform's state files. 
Also, relying on successive stop/restart cycles would be an encouragement 
to make successive and possibly undocumented amendment to the instance; 
wiping the slate clean every time forces us to code changes 'at the source' in the AMI.
  

### Rolling out a new machine image

Amend the Packer template and its associated files and scripts. 
Run `packer build image.json` to create the new AMI on AWS.
Destroy and recreate the EC2 instance like above; 
the Terraform configuration will automatically select
the latest version of the AMI.

### Recreating both EBS volume and EC2 instance 

Save a [snapshot of the EBS volume](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSSnapshots.html) 
if you wish to keep its data.

Run `terraform destroy`, first in `terraform/ec2` and then in `terraform/ebs`. 
Amend the terraform configuration files if needed, in particular if
the new EBS volume should be based on a snapshot taken earlier
(see [aws_ebs_volume](https://www.terraform.io/docs/providers/aws/r/ebs_volume.html)).
Then run `terraform apply`, first in `terraform/ebs` and then 
in `terraform/ec2`.



## Terraform notes 

Since the machine's is provisioned at AMI level by Packer, 
our Terraform configuration is generic and directly
reusable for other projects. 

Below a couple of comments about the Terraform code.

### Changing ssh port

The ssh port of the instance can be changed from the onset 
by passing a script to the `user_data` property of the `aws_instance`. 
This will be directly executed as `root` by AWS when the instance is created. 
The code below uses `sed` to replace the `#Port 22` line in `/etc/ssh/sshd_config` 
with a new port, and it then restarts the ssh server:

```hcl-terraform
user_data = "#!/bin/bash\nsed -i 's/#Port 22/Port ${var.ssh_port}/g' /etc/ssh/sshd_config && service sshd restart"
```

The `user_data` block is executed before Terraform runs provisioners, so Terraform 
provisioners only need to know about the new port. 
 
### Mounting and unmounting EBS volumes with Terraform
 
Terraform allows attaching an EBS volume to an EC2 instance via a 
resource called `aws_volume_attachment`. It's pretty straightforward: you specify 
an `aws_instance` and an `aws_ebs_volume`, and you then specify their attachment 
with `aws_volume_attachment`. 

```hcl-terraform
resource "aws_volume_attachment" "clojure" {
  device_name = "/dev/sdd"
  volume_id = "${data.aws_ebs_volume.clojure.id}"
  instance_id = "${aws_instance.clojure.id}"  
}
```

In its simplest form above, `aws_volume_attachment` 
only attaches the volume as a device (e.g. `/dev/sdd`), but it doesn't 
mount it onto a folder. Terraform will also refuse 
to destroy the attachment if the device is already mounted (although 
there is an option to add `force_detach = true` to force the detachment). 

Getting  granular control of the mounting and unmounting process with Terraform
[can come across as a confusing matter](https://github.com/hashicorp/terraform/issues/2957).
However, using `remote_exec` provisiones within the `aws_volume_attachment` does provide
such granular control. 
The key here is to give these provisioners the proper ssh `connection`
so that they can connect to the `aws_instance` and run 
provisioning commands/scripts. Terraform's 'interpolation syntax'
makes this easy, by providing the hostname of the instance via 
`"${aws_instance.my-instance.public_dns}"`. Below the code of the 
`aws_volume_attachment` in `terraform/ec2/main.tf`:

```hcl-terraform
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
```

The result of this code is that Terraform will run `ebs-mount` via ssh onto
the instance once the attachment is created; and it will run `ebs-unmount` before
destroying the attachment. My codes for `ebs-mount` and `ebs-unmount`
can be found in `ec2/scripts`. `ebs-mount` detects whether
the volume needs to be formatted or not before mounting. `ebs-unmount`
sends a kill signal to processes that use the device before unmounting it.
I'm not a linux expert though, and these scripts can certainly be improved.
Nevertheless, using `remote_exec` provisioners as above
seems an idiomatic way to mount/unmount volumes via `aws_volume_attachment`
and to tailor the process to one's needs. 

## License

Copyright © 2018 Nicolas Duchenne, [Belove Ltd](https://www.belove.co.uk), London, UK

Distributed under the 
[Creative Commons Attribution 4.0 (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/) 
license.
