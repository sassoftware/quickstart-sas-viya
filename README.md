# quickstart-sas-viya

This Quick Start provides a reliable and automated way to install and configure SAS Viya Software AWS.

The Quick Start deploys SAS Viya into a AWS VPC. You can choose to deploy SAS Viya into a new or your existing AWS environment.

![Quick Start SAS Viya Design Architecture](images/sas-viya-architecture-diagram.png)

The Quick Start provides parameters that you can set to customize your deployment. For architectural details, best practices, step-by-step instructions, and customization options, see the deployment guide: []

## What you'll build 

Use this Quick Start to set up the following configurable environment on AWS:
   
   - A virtual private cloud (VPC) configured with public and private subnets according to AWS best practices. This provides the network infrastructure for your SAS Viya deployment.*
   - An Internet gateway to provide access to the Internet.*
   - Managed NAT gateways to allow outbound Internet access for resources in the private subnets.*
   - In the private subnet, 2 EC2 instances for SAS Viya deployment.
   - In the public subnet, an EC2 instance used as bastion host that serves as an admin node, allowing access to the SAS Viya VMs in the private subnet.
   - Security groups for the SAS Viya VMs and the bastion host.
   - A CloudWatch group for deployment and application logs.
   - Optionally, a SNS Email Notification with SAS Viya deployment start and completion messages. 
   - Your choice to create a new VPC or deploy into your existing VPC on AWS. The template that deploys the Quick Start into an existing VPC skips the components marked by asterisks above.
   
   For details, see the Quick Start deployment guide.
   
## Deployment details



## Cost and licenses