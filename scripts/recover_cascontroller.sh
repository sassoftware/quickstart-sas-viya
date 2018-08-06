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
PRIVATE_IP=$(cat /etc/hosts | grep controller | cut -d" " -f1)

#
# get CAS controller volume ids
#
CASLIB_VOLUME=$(aws --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name {{Stack}} --query 'StackResources[?LogicalResourceId==`CASLibVolume`].PhysicalResourceId' --output text)
CASVIYA_VOLUME=$(aws --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name {{Stack}} --query 'StackResources[?LogicalResourceId==`CASViyaVolume`].PhysicalResourceId' --output text)

#
# check that we have values for all required variables
#
test -n {{ImageId}}
test -n {{InstanceType}}
test -n {{KeyName}}
test -n {{PlacementGroupName}}
test -n {{SecurityGroupIds}}
test -n {{SubnetId}}
test -n {{IamInstanceProfile}}
test -n {{RAIDScript}}
test -n $PRIVATE_IP
test -n $CASLIB_VOLUME
test -n $CASVIYA_VOLUME

#
# create new instance
#
NEW_ID=$(aws --region "{{AWSRegion}}"  ec2 run-instances \
--image-id {{ImageId}} \
--instance-type {{InstanceType}} \
--key-name {{KeyName}} \
--placement GroupName={{PlacementGroupName}} \
--security-group-ids {{SecurityGroupIds}} \
--subnet-id {{SubnetId}} \
--iam-instance-profile Name={{IamInstanceProfile}} \
--private-ip-address $PRIVATE_IP \
--user-data \
  '#!/bin/bash
   export PATH=$PATH:/usr/local/bin
   # install aws cli
   curl -O https://bootstrap.pypa.io/get-pip.py && python get-pip.py &> /dev/null
   pip install awscli --ignore-installed six &> /dev/null
   KEY=$(aws ssm get-parameter --region "{{AWSRegion}}" --name "viya-ansiblekey-{{Stack}}" --query Parameter.Value --output text)
   echo "$KEY" | su ec2-user bash -c "tee -a ~/.ssh/authorized_keys"' \
--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value={{Stack}} CAS Controller}]" \
--query 'Instances[0].InstanceId' --output text
)

echo NEW_ID=$NEW_ID
time aws --region "{{AWSRegion}}" ec2 wait instance-running --instance-ids $NEW_ID

# attach volumes
aws --region "{{AWSRegion}}" ec2 attach-volume --instance-id $NEW_ID --device /dev/sdg --volume-id $CASLIB_VOLUME
aws --region "{{AWSRegion}}" ec2 attach-volume --instance-id $NEW_ID --device /dev/sdl --volume-id $CASVIYA_VOLUME


# remove old host key from ansible controller
ssh-keygen -R $PRIVATE_IP
ssh-keygen -R controller.viya.sas
ssh-keygen -R controller

# wait for sshd on the new VM to become available
while ! ssh -o StrictHostKeyChecking=no $PRIVATE_IP 'exit' 2>/dev/null
do
  sleep 1
done

# seed known_hosts file on ansible-controller
ssh -o StrictHostKeyChecking=no $PRIVATE_IP exit
ssh -o StrictHostKeyChecking=no controller.viya.sas exit
ssh -o StrictHostKeyChecking=no controller exit

# reconfigure
pushd ~/sas_viya_playbook
  # mount volumes, update /etc/hosts/ file
  ansible-playbook ansible.pre.deployment.yml -e "AWSRegion='{{AWSRegion}}'" \
                                              -e "RAIDScript='{{RAIDScript}}'" \
                                              -e "CloudFormationStack='{{Stack}}'" \
                                              --limit=controller

  # apply prereqs
  ansible-playbook virk/playbooks/pre-install-playbook/viya_pre_install_playbook.yml \
      --skip-tags skipmemfail,skipcoresfail,skipstoragefail,skipnicssfail,bandwidth -e 'use_pause=false' --limit=controller

  # re-install services
  ansible-playbook site.yml

  # configure PAM and set up users
  if [ -d ~/openldap ]; then
    pushd ~/openldap
    USERPASS=$(echo -n '{{{SASUserPass}}}' | base64)
    ADMINPASS=$(echo -n '{{{SASAdminPass}}}' | base64)
    ansible-playbook openldapsetup.yml -e "OLCROOTPW='$ADMINPASS' OLCUSERPW='$USERPASS'" --tags common,client
    popd
  fi

popd



