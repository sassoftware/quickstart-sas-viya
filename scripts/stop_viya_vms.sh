#!/bin/bash

# Run this script to stop all Viya services and all VMs where they are running.
#
# Use this script in combination with start_viya_vms.sh to save AWS resource costs
# when the SAS Viya environment is not actively in use.

# Expect the script to run about 10 minutes

#
# execute the virk stop services playbook
#
echo "Stopping Viya services..."

pushd /sas/install/ansible/sas_viya_playbook
   # It is necessary to disable the automatic service restarts.
   # Without disabling the service restart, the services will come up as each VM restarts.
   # Instead, we want to control the order at restart.
   ansible-playbook viya-ark/playbooks/viya-mmsu/viya-services-disable.yml
   # This stops the services in the correct order
   ansible-playbook viya-ark/playbooks/viya-mmsu/viya-services-stop.yml
popd


#
# get all the VMs of the stack, except the ansible controller
#
echo "Getting list of VMs..."

# get the instance id from the instance metadata
INSTANCE_ID=$( curl -s http://169.254.169.254/latest/meta-data/instance-id )

# get the aws region from the instance metadata
AWS_AVAIL_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
AWS_REGION=$(echo ${AWS_AVAIL_ZONE}  | sed "s/[a-z]$//")

# get the stack name from the automatic instance tag "aws:cloudformation:stack-name"
STACK_NAME=$(aws --region $AWS_REGION ec2 describe-tags --filter "Name=resource-id,Values=$INSTANCE_ID" --query 'Tags[?Key==`aws:cloudformation:stack-name`].Value' --output text)


IDS=$(aws --region $AWS_REGION cloudformation describe-stack-resources --stack-name $STACK_NAME --query 'StackResources[?ResourceType==`AWS::EC2::Instance`  && LogicalResourceId!=`AnsibleController`].PhysicalResourceId' --output text)

for stack in $(aws  --region $AWS_REGION cloudformation describe-stack-resources --stack-name $STACK_NAME --query 'StackResources[?ResourceType==`AWS::CloudFormation::Stack`].PhysicalResourceId' --output text); do
	IDS="$IDS $(aws --region $AWS_REGION cloudformation describe-stack-resources --stack-name $stack --query 'StackResources[?ResourceType==`AWS::EC2::Instance`].PhysicalResourceId' --output text)"
done

#
# stop the VMs
#
echo "Stopping VMs..."
aws --region $AWS_REGION ec2 stop-instances --instance-ids ${IDS}
