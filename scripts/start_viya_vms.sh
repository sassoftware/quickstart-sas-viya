#!/bin/bash

set -e  # stop script on error

# Run this script to start all the Viya VMs and Viya services.
#
# Use this script in combination with stop_viya_vms.sh to save AWS resource costs
# when the SAS Viya environment is not actively in use.

# Expect the script to run about 10 minutes

echo "Getting list of VMs..."
# get the instance id from the instance metadata
INSTANCE_ID=$( curl -s http://169.254.169.254/latest/meta-data/instance-id )

# get the aws region from the instance metadata
AWS_AVAIL_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
AWS_REGION=$(echo ${AWS_AVAIL_ZONE}  | sed "s/[a-z]$//")

# get the stack name from the automatic instance tag "aws:cloudformation:stack-name"
STACK_NAME=$(aws --region $AWS_REGION ec2 describe-tags --filter "Name=resource-id,Values=$INSTANCE_ID" --query 'Tags[?Key==`aws:cloudformation:stack-name`].Value' --output text)

# get all the VMs of the stack, except the ansible controller
IDS=$(aws --region $AWS_REGION cloudformation describe-stack-resources --stack-name $STACK_NAME --query 'StackResources[?ResourceType==`AWS::EC2::Instance`  && LogicalResourceId!=`AnsibleController`].PhysicalResourceId' --output text)
# transform into array
IFS=" " IDs=(${IDS})
unset IFS


#
# start the VMs
#
echo "Starting VMs..."
aws --region $AWS_REGION ec2 start-instances --instance-ids ${IDS}


#
# wait for the VMs to be up
#
STATUS=
while [ "$STATUS" = "" ]; do
   sleep 3
   if [ -z "$(aws --region $AWS_REGION ec2 describe-instances --instance-ids $IDS --query Reservations[*].Instances[*].State.Name --output text | grep -q -v 'running')" ] ; then
     STATUS='ok'
   fi

   # make sure sshd is up on each VM
   for ID in ${IDs[@]}; do
      IP=$(aws ec2 --region $AWS_REGION describe-instances --instance-id $ID --query Reservations[*].Instances[*].PrivateIpAddress --output text)
      RC=-1
      until [ $RC = 0 ]; do
        sleep 3
        # try to log in
        ssh -q $IP exit
        RC=$?
      done
   done
done


#
# execute the virk start services playbook
#
echo "Starting Viya services..."
pushd /sas/install/ansible/sas_viya_playbook
    # start the services in the correct order
    ansible-playbook virk/playbooks/service-management/viya-services-start.yml
popd

