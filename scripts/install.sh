#!/bin/bash

# this script is expect to be run by a user with sudo privileges (typically ec2-user)

trap cleanup EXIT

set -o pipefail
set -o errexit
set -o nounset


# This is a mustache template.
# Make sure all the input parms are set
test -n "{{ViyaServicesNodeIP}}"
test -n "{{CASControllerNodeIP}}"
test -n "{{SASViyaAdminPassword}}"
test -n "{{LogGroup}}"
test -n "{{AWSRegion}}"
test -n "{{KeyPairName}}"
test -n "{{BastionIPV4}}"
test -n "{{CloudFormationStack}}"
test -n "{{CloudWatchLogs}}"
test -n "{{SASHome}}"
test -n "{{SASStudio}}"



create_start_message () {

cat <<EOF > /tmp/sns_start_message.txt

  Starting SAS Viya Deployment for Stack "{{CloudFormationStack}}".

  Follow the deployment logs at {{CloudWatchLogs}}

  Log into the Administrator VM with the private key for KeyPair "{{KeyPairName}}":

       ssh -i /path/to/private/key.pem ec2-user@{{BastionIPV4}}

  Viya Services Node IP:  {{ViyaServicesNodeIP}}
  CAS Controller Node IP: {{CASControllerNodeIP}}

EOF

}

create_success_message () {

    ## on success, add link to all endpoints, and the bastion ip and keyname
cat <<EOF > /tmp/sns_success_message.txt

   SAS Viya Deployment for Stack "{{CloudFormationStack}}" completed successfully.

   Log into SAS Viya at {{SASHome}}

   Log into SAS/Studio at {{SASStudio}}

   Log into the Administrator VM with the private key for KeyPair "{{KeyPairName}}":

       ssh -i /path/to/private/key.pem ec2-user@{{BastionIPV4}}

EOF

}

create_failure_message ( ) {

cat <<EOF > /tmp/sns_failure_message.txt

   SAS Viya Deployment for Stack "{{CloudFormationStack}}" failed with RC=$1.

   Check the deployment logs at {{CloudWatchLogs}}.

EOF

}

if [ -n "{{SNSTopic}}" ]; then

  # create and send start email

  create_start_message

  aws --region {{AWSRegion}} sns publish --topic-arn {{SNSTopic}} \
      --subject "Starting SAS Viya Deployment" \
      --message file:///tmp/sns_start_message.txt

fi



cleanup () {

  RC=$?

  if [ -n "{{SNSTopic}}" ]; then

    if [[ $RC == 0 ]]; then

      # create and send success email

      create_success_message

      aws --region {{AWSRegion}} sns publish --topic-arn {{SNSTopic}} \
          --subject "SAS Viya Deployment {{CloudFormationStack}} completed." \
          --message file:///tmp/sns_success_message.txt

    else

      # create and send failure email

      create_failure_message $RC

      aws --region {{AWSRegion}} sns publish --topic-arn {{SNSTopic}} \
          --subject "SAS Viya Deployment {{CloudFormationStack}} failed." \
          --message file:///tmp/sns_failure_message.txt

    fi

  fi

  cfn-signal -e $RC --stack {{CloudFormationStack}} --resource BastionHost --region {{AWSRegion}}

}

# sometimes there are ssh connection errors (53) during the install
# this function allows to retry N times
try () {
  # allow up to N attempts of a command
  # syntax: try N [command]

  max_count=$1
  shift
  count=1
  until  $@  || [ $count -gt $max_count  ]
  do
    let count=count+1
  done
}

addLogFileToCloudWatch () {

# add file to CloudWatch configuration and restart CloudWatch agent

LOGFILE=$1
cat <<EOF | sudo tee -a /etc/awslogs/awslogs.conf

[$LOGFILE]
log_stream_name = $LOGFILE
initial_position = start_of_file
file = $(pwd)/$LOGFILE
log_group_name = {{LogGroup}}
EOF

sudo service awslogs restart

}


# prepare inventory.ini header
echo deployTarget ansible_ssh_host={{ViyaServicesNodeIP}} > /tmp/inventory.head
echo controller ansible_ssh_host={{CASControllerNodeIP}} >> /tmp/inventory.head

# set up OpenLDAP
pushd openldap

  # set log file
  export ANSIBLE_LOG_PATH=openldap-deployment.log
  touch $ANSIBLE_LOG_PATH
  addLogFileToCloudWatch $ANSIBLE_LOG_PATH

  # add hosts
  ansible-playbook update.inventory.yml

  # openldap and sssd setup
  try 3 ansible-playbook openldapsetup.yml

popd



# untar playbook
tar xf /tmp/SAS_Viya_playbook.tgz

pushd sas_viya_playbook

  # copy additional playbooks
  mv /tmp/ansible.* .

  # get identities configuration from openldap setup
  cp ../openldap/sitedefault.yml roles/consul/files/

  # set log file for pre deployment steps
  export ANSIBLE_LOG_PATH=viya-pre-deployment.log
  touch $ANSIBLE_LOG_PATH
  addLogFileToCloudWatch $ANSIBLE_LOG_PATH

  # add hosts to inventory
  ansible-playbook ansible.update.inventory.yml

  # set prereqs on hosts
  try 3 ansible-playbook ansible.pre.deployment.yml

  # set log file for main deployment
  export ANSIBLE_LOG_PATH=viya-deployment.log
  touch $ANSIBLE_LOG_PATH
  addLogFileToCloudWatch $ANSIBLE_LOG_PATH

  # main deployment
  ansible-playbook ansible.update.vars.file.yml
  try 3 ansible-playbook site.yml
  ansible-playbook ansible.post.deployment.yml -e "sasboot_pw={{SASViyaAdminPassword}}"

popd

