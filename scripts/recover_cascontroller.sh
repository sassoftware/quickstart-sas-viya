#!/bin/bash -e

# Run this script to recover the CAS controller if it experienced a catastrophic failure and
# did not automatically recover.
# Please note that this script should be used for recovery from a catastrophic event only.
#
# All VMs in this deployment use the EC2 Auto-Recovery feature
# (see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-recover.html)
# The i3 instance type does not support auto recovery. If you chose that instance
# type for the CAS controller (which is the type SAS recommends), the CAS controller
# VM may stay unusable after a catastrophic failure.
#
# To recover the CAS controller, this script has been created by the
# original deployment with most of the attributes necessary to create a EC2 VM similar to the
# original CAS Controller VM.
# In addition, the script retrieves the original private ip address, and the
# EBS volumes that were attached to the CAS Controller.
#
# The script uses that information to create a VM with the original IP address,
# and re-attaches and mountsthe same EBS volumes, retaining the SAS Viya install and any user data.
#
# The script then configures the VM and re-installs and starts the
# required Viya system services, by re-running some of the ansible playbooks used for the
# original install. This part may take about 30 minutes to finish.
#
# The script also recreates the PAM configuration for the default openLDAP setup, and
# sets up local accounts for sasadmin and sasuser on the new controller VM.
# If your deployment does not use the default openLDAP setup (i.e. no SASUserPass parameter
# was set at Stack creation), you will need to set the PAM configuration and local users
# on the new VM to match your original post-configuration.
#
# For the CloudFormation stack, running this script means that we are creating a out-of-process resource.
# This new VM is not managed by the CloudFormation stack. That means, when you delete the Stack,
# the new CAS Controller will not be be terminated.
#
# Before you delete the Stack, first terminate the CAS Controller VM.
# Otherwise, the Stack deletion will not be able to complete, because the
# following resources are being held by the CAS Controller:
# AnsibleControllerSecurityGroup
# CASLibVolume
# CASViyaVolume
# ViyaPlacementGroup
# ViyaSecurityGroup




#
# get private ip address of cas controller
#
CONTROLLER_IP=$(cat /etc/hosts | grep controller | cut -d" " -f1)

#
# get ansible controller private IP
#
ANSIBLE_IP=$(hostname -i)


#
# get the aws region from the instance metadata
#
AWS_AVAIL_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
AWS_REGION=$(echo ${AWS_AVAIL_ZONE}  | sed "s/[a-z]$//")

#
# get the stack name from the automatic instance tag "aws:cloudformation:stack-name"
#
INSTANCE_ID=$( curl -s http://169.254.169.254/latest/meta-data/instance-id )
STACK_NAME=$(aws --region $AWS_REGION ec2 describe-tags --filter "Name=resource-id,Values=$INSTANCE_ID" --query 'Tags[?Key==`aws:cloudformation:stack-name`].Value' --output text)


#
# get CAS controller volume ids
#
CASLIB_VOLUME=$(aws --region "$AWS_REGION" cloudformation describe-stack-resources --stack-name $STACK_NAME --query 'StackResources[?LogicalResourceId==`CASLibVolume`].PhysicalResourceId' --output text)
CASVIYA_VOLUME=$(aws --region "$AWS_REGION" cloudformation describe-stack-resources --stack-name $STACK_NAME --query 'StackResources[?LogicalResourceId==`CASViyaVolume`].PhysicalResourceId' --output text)

#
# check that we have values for all required variables
#
test -n {{ControllerImageId}}
test -n {{ControllerInstanceType}}
test -n {{KeyPairName}}
test -n {{PlacementGroupName}}
test -n {{SecurityGroupId}}
test -n {{SubnetId}}
test -n {{IamInstanceProfile}}
test -n {{S3_FILE_ROOT}}
test -n $CONTROLLER_IP
test -n $ANSIBLE_IP
test -n $CASLIB_VOLUME
test -n $CASVIYA_VOLUME
test -n $STACK_NAME
test -n $AWS_REGION

#
# create new instance
#
NEW_ID=$(aws --region "$AWS_REGION"  ec2 run-instances \
--image-id {{ControllerImageId}} \
--instance-type {{ControllerInstanceType}} \
--key-name {{KeyPairName}} \
--placement GroupName={{PlacementGroupName}} \
--security-group-ids {{SecurityGroupId}} \
--subnet-id {{SubnetId}} \
--iam-instance-profile Name={{IamInstanceProfile}} \
--private-ip-address $CONTROLLER_IP \
--user-data \
  '#!/bin/bash
   export PATH=$PATH:/usr/local/bin
   curl -O https://bootstrap.pypa.io/get-pip.py && python get-pip.py &> /dev/null
   pip install awscli --ignore-installed six &> /dev/null

   aws s3 cp s3://{{S3_FILE_ROOT}}common/scripts/sasnodes_prereqs.sh /tmp/prereqs.sh
   chmod +x /tmp/prereqs.sh
   su -l ec2-user -c "NFS_SERVER='${ANSIBLE_IP}' HOST=controller /tmp/prereqs.sh &>/tmp/prereqs.log"
  ' \
--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$STACK_NAME CAS Controller}]" \
--query 'Instances[0].InstanceId' --output text
)



echo NEW_ID=$NEW_ID
time aws --region "$AWS_REGION" ec2 wait instance-running --instance-ids $NEW_ID

# attach volumes
aws --region "$AWS_REGION" ec2 attach-volume --instance-id $NEW_ID --device /dev/sdg --volume-id $CASLIB_VOLUME
aws --region "$AWS_REGION" ec2 attach-volume --instance-id $NEW_ID --device /dev/sdl --volume-id $CASVIYA_VOLUME


# remove old host key from ansible controller
ssh-keygen -R $CONTROLLER_IP
ssh-keygen -R controller.viya.sas
ssh-keygen -R controller

# wait for sshd on the new VM to become available
while ! ssh -o StrictHostKeyChecking=no $CONTROLLER_IP 'exit' 2>/dev/null
do
  sleep 1
done

# seed known_hosts file on ansible-controller
ssh -o StrictHostKeyChecking=no $CONTROLLER_IP exit
ssh -o StrictHostKeyChecking=no controller.viya.sas exit
ssh -o StrictHostKeyChecking=no controller exit

#
# confingure VM and reinstall viya
#

# set log file
export ANSIBLE_LOG_PATH=/var/log/sas/install/recover_cascontroller.log

#
# node setup
#
export ANSIBLE_CONFIG=/sas/install/common/ansible/playbooks/ansible.cfg
ansible-playbook -v /sas/install/common/ansible/playbooks/prepare_nodes.yml \
  -e "USERLIB_DISK=/dev/xvdl" \
  -e "SAS_INSTALL_DISK=/dev/xvdg" \
  -l CASControllerServer


#
# OpenLDAP/PAM configuration
#
if [ -n "{{{SASUserPass}}}" ] && [ -n "{{{SASAdminPass}}}" ]; then
    USERPASS=$(echo -n '{{{SASUserPass}}}' | base64)
    ADMINPASS=$(echo -n '{{{SASAdminPass}}}' | base64)
    ansible-playbook -v /sas/install/common/ansible/playbooks/openldapsetup.yml \
      -e "OLCROOTPW='${ADMINPASS}'" \
      -e "OLCUSERPW='${USERPASS}'" \
      --tags openldapcommon,openldapclients
fi

unset ANSIBLE_CONFIG
pushd /sas/install/ansible/sas_viya_playbook
    #
    # VM prereqs
    #
    ansible-playbook -v virk/playbooks/pre-install-playbook/viya_pre_install_playbook.yml \
         -e "use_pause=false" \
         --skip-tags skipmemfail,skipcoresfail,skipstoragefail,skipnicssfail,bandwidth \
         -l CASControllerServer
    #
    # rerun viya install
    #
    ansible-playbook site.yml
popd

export ANSIBLE_CONFIG=/sas/install/common/ansible/playbooks/ansible.cfg
ansible-playbook -v /sas/install/common/ansible/playbooks/post_deployment.yml

