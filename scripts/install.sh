#!/bin/bash

# this script is expected to be run by a user with sudo privileges (typically ec2-user)

trap cleanup EXIT

set -o pipefail
set -o errexit
set -o nounset


# This is a mustache template.
# Make sure all the input parms are set
test -n "{{ViyaServicesIP}}"
test -n "{{CASControllerIP}}"
test -n "{{ViyaAdminPass}}"
test -n "{{ViyaUserPass}}"
test -n "{{LogGroup}}"
test -n "{{AWSRegion}}"
test -n "{{KeyPairName}}"
test -n "{{AnsibleControllerIP}}"
test -n "{{CloudFormationStack}}"
test -n "{{CloudWatchLogs}}"
test -n "{{SASHome}}"
test -n "{{SASStudio}}"
test -n "{{CASMonitor}}"



create_start_message () {

cat <<EOF > /tmp/sns_start_message.txt

  Starting SAS Viya Deployment for Stack "{{CloudFormationStack}}".

  Follow the deployment logs at {{CloudWatchLogs}}

  Log into the Ansible Controller VM with the private key for KeyPair "{{KeyPairName}}":

       ssh -i /path/to/private/key.pem ec2-user@{{AnsibleControllerIP}}

  Viya Services IP:  {{ViyaServicesIP}}
  CAS Controller IP: {{CASControllerIP}}
EOF

[ -n "{{CASWorker1IP}}" ] && echo "  CAS Worker 1 IP: {{CASWorker1IP}}" >> /tmp/sns_start_message.txt || :
[ -n "{{CASWorker2IP}}" ] && echo "  CAS Worker 2 IP: {{CASWorker2IP}}" >> /tmp/sns_start_message.txt || :
[ -n "{{CASWorker3IP}}" ] && echo "  CAS Worker 3 IP: {{CASWorker3IP}}" >> /tmp/sns_start_message.txt || :
[ -n "{{CASWorker4IP}}" ] && echo "  CAS Worker 4 IP: {{CASWorker4IP}}" >> /tmp/sns_start_message.txt || :

}

create_success_message () {

    ## on success, add link to all endpoints, and the ansible controller ip and keyname
cat <<EOF > /tmp/sns_success_message.txt

   SAS Viya Deployment for Stack "{{CloudFormationStack}}" completed successfully.

   Log into SAS Viya at {{SASHome}}

   Log into SAS Studio at {{SASStudio}}

   Log into CAS Server Monitor at {{CASMonitor}}

   Log into the Ansible Controller VM with the private key for KeyPair "{{KeyPairName}}":

       ssh -i /path/to/private/key.pem ec2-user@{{AnsibleControllerIP}}

  Viya Services IP:  {{ViyaServicesIP}}
  CAS Controller IP: {{CASControllerIP}}
EOF

[ -n "{{CASWorker1IP}}" ] && echo "  CAS Worker 1 IP: {{CASWorker1IP}}" >> /tmp/sns_start_message.txt || :
[ -n "{{CASWorker2IP}}" ] && echo "  CAS Worker 2 IP: {{CASWorker2IP}}" >> /tmp/sns_start_message.txt || :
[ -n "{{CASWorker3IP}}" ] && echo "  CAS Worker 3 IP: {{CASWorker3IP}}" >> /tmp/sns_start_message.txt || :
[ -n "{{CASWorker4IP}}" ] && echo "  CAS Worker 4 IP: {{CASWorker4IP}}" >> /tmp/sns_start_message.txt || :

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
      --subject "Starting SAS Viya Deployment {{CloudFormationStack}}" \
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

  cfn-signal -e $RC --stack {{CloudFormationStack}} --resource AnsibleController --region {{AWSRegion}}

}


# sometimes there are ssh connection errors (53) during the install
# this function allows to retry N times
function try () {
  # allow up to N attempts of a command
  # syntax: try N [command]

  count=1; max_count=$1; shift
  until  $@  || [ $count -gt $max_count ]; do
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




# prepare host list for ansible inventory.ini file
echo deployTarget ansible_host={{ViyaServicesIP}} > /tmp/inventory.head
echo controller ansible_host={{CASControllerIP}} >> /tmp/inventory.head
[ -n "{{CASWorker1IP}}" ] && echo worker1 ansible_host={{CASWorker1IP}} >> /tmp/inventory.head || :
[ -n "{{CASWorker2IP}}" ] && echo worker2 ansible_host={{CASWorker2IP}} >> /tmp/inventory.head || :
[ -n "{{CASWorker3IP}}" ] && echo worker3 ansible_host={{CASWorker3IP}} >> /tmp/inventory.head || :
[ -n "{{CASWorker4IP}}" ] && echo worker4 ansible_host={{CASWorker4IP}} >> /tmp/inventory.head || :


# set up OpenLDAP
pushd openldap

  sed -i "s/{{SASViyaAdminPassword}}/sasviyapw/" group_vars/all.yml

  # set log file
  export ANSIBLE_LOG_PATH=openldap-deployment.log
  touch $ANSIBLE_LOG_PATH
  addLogFileToCloudWatch $ANSIBLE_LOG_PATH

  # add hosts
  ansible-playbook update.inventory.yml

  # openldap and sssd setup
  ansible-playbook openldapsetup.yml -e "OLCROOTPW={{ViyaAdminPass}} OLCUSERPW={{ViyaUserPass}}"

popd


## get orchestration cli
### extract certificates
#sudo unzip -j /tmp/SAS_Viya_deployment_data.zip "entitlement-certificates/entitlement_certificate.pem" -d "/etc/pki/sas/private/"
#sudo unzip -j /tmp/SAS_Viya_deployment_data.zip "ca-certificates/SAS_CA_Certificate.pem" -d "/etc/ssl/certs/"
#
## Download the RPM file used to establish yum connectivity to the central SAS
## catalog of repositories
#sudo curl -OLv --cert /etc/pki/sas/private/entitlement_certificate.pem --cacert /etc/ssl/certs/SAS_CA_Certificate.pem https://ses.sas.download/ses/repos/meta-repo//sas-meta-repo-1-1.noarch.rpm
#
## Install the downloaded RPM file
#sudo yum -y install sas-meta-repo-1-1.noarch.rpm
#
## Install the main repository
#sudo yum -y install sas-va-101_ea160-x64_redhat_linux_6-yum
#
## install the orchestration cli
#sudo yum -y install sas-orchestration-cli

# or (yet to try)
#
#curl -kO https://repulpmaster.unx.sas.com/pulp/repos/release-testready/va/101.0/va-101.0.0-x64_redhat_linux_6-yum-testready/sas-orchestration-cli-1.0.13-20171009.1507582997914.x86_64.rpm
#
#Then you can extract it as you described using a command like this.
#
#rpm2cpio ./sas-orchestration-cli-1.0.13-20171009.1507582997914.x86_64.rpm | cpio -idmv
#
#What will be written locally is as follows
#
#Linux: ./opt/sas/viya/home/bin/sas-orchestration
#OSX: ./opt/sas/viya/home/share/sas-orchestration/osx/sas-orchestration
#Windows: ./opt/sas/viya/home/share/sas-orchestration/windows/sas-orchestration.exe
#
#If you happen to be on a RHEL box and want to install the RPM to that system, you should also be able to do
#
#rpm -i ./sas-orchestration-cli-1.0.13-20171009.1507582997914.x86_64.rpm

## make sure the other VMs are all up
#STATUS="status"
#while ! [ $(echo "$STATUS" | wc -w)  -eq $(echo "$STATUS" | grep CREATE_COMPLETE | wc -w) ]; do
#  sleep 3
#  STATUS=$(aws cloudformation  describe-stack-resources --region {{AWSRegion}} --stack-name {{CloudFormationStack}}  --output json --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId != `AnsibleController`].ResourceStatus' --output text)
#  [ $(echo "$STATUS" | grep "CREATE_FAILED") ]  && exit 1 || :
#done
# needs these permissions:
#
#    "Action": [
#                "cloudformation:DescribeStackResources"
#            ],
#            "Resource": "arn:aws:cloudformation:*:*:stack/mpp04/*",
#            "Effect": "Allow"
#        }


# location of installed cli: /opt/sas/viya/home/bin/sas-orchestration

# build playbook
/tmp/sas-orchestration build --input  /tmp/SAS_Viya_deployment_data.zip

# untar playbook
tar xf SAS_Viya_playbook.tgz

pushd sas_viya_playbook

  check_license ()
  {
    # number of licensed cores for CAS

    # cat,xargs,sed: create single, semicolon-terminated lines;
    UNWRAPPED=$(cat  SASViyaV0300_*_Linux_x86-64.txt | xargs | sed 's/;/;\n/g')
    CPUNUM=$(echo "$UNWRAPPED" | grep EXPIRE | grep PRODNUM1141 | sed -r "s/.*CPU=(.*)\;/\1/")
    LICCORES=$(echo "$UNWRAPPED" | grep NAME=$CPUNUM | sed  -r "s/.*SERIAL=\+([0-9]+).*/\1/")

    CPUCOUNT=$(ssh {{CASControllerIP}} cat /proc/cpuinfo | grep -c ^processor)
    let CPUCOUNT=CPUCOUNT/2

    WORKERCOUNT=$(cat /tmp/inventory.head  | grep worker | wc -l)
    let CASNODESCOUNT=WORKERCOUNT+1

    let USEDCORES=CASNODESCOUNT*CPUCOUNT

    echo Licensed Cores = $LICCORES
    echo Used Cores = $USEDCORES

  }

  # copy additional playbooks
  chmod +w ansible.cfg
  cp /tmp/ansible.* .

  # get identities configuration from openldap setup
  cp ../openldap/sitedefault.yml roles/consul/files/

  # set log file for pre deployment steps
  export ANSIBLE_LOG_PATH=viya-pre-deployment.log
  touch $ANSIBLE_LOG_PATH
  addLogFileToCloudWatch $ANSIBLE_LOG_PATH

  # add hosts to inventory
  ansible-playbook ansible.update.inventory.yml

  # set prereqs on hosts
  ansible-playbook ansible.pre.deployment.yml

  # set log file for main deployment
  export ANSIBLE_LOG_PATH=viya-deployment.log
  touch $ANSIBLE_LOG_PATH
  addLogFileToCloudWatch $ANSIBLE_LOG_PATH

  # main deployment
  ansible-playbook ansible.update.vars.file.yml
  try 2 ansible-playbook site.yml

  # Only for EA: copy the redshift resources
  ansible-playbook ansible.post.deployment.yml --tags "EA"

popd

