#!/bin/bash
set -x

# this script is expected to be run by a user with sudo privileges (typically ec2-user)

trap cleanup EXIT

set -o pipefail
set -o errexit
set -o nounset


# This is a mustache template.
# Make sure all the input parms are set
test -n "{{SASAdminPass}}"
test -n "{{SASUserPass}}"
test -n "{{LogGroup}}"
test -n "{{AWSRegion}}"
test -n "{{KeyPairName}}"
test -n "{{AnsibleControllerIP}}"
test -n "{{NumWorkers}}"
test -n "{{CloudFormationStack}}"
test -n "{{CloudWatchLogs}}"


VisualServicesIP=
ProgrammingServicesIP=
StatefulServicesIP=
CASControllerIP=
CASWorker1IP=
CASWorker2IP=
CASWorker3IP=
DomainName=



# prepare directories for logs and messages
export LOGDIR=$HOME/deployment-logs
mkdir -p "$LOGDIR"
export MSGDIR=$HOME/deployment-messages
mkdir -p "$MSGDIR"



create_start_message () {

OUTFILE="$MSGDIR/sns_start_message.txt"

cat <<EOF > "$OUTFILE"

  Starting SAS Viya Deployment for Stack "{{CloudFormationStack}}".

  Follow the deployment logs at {{CloudWatchLogs}}

  Log into the Ansible Controller VM with the private key for KeyPair "{{KeyPairName}}":

       ssh -i /path/to/private/key.pem ec2-user@{{AnsibleControllerIP}}

  From the ansible controller, you can ssh into these VMs:

       Visual Services:
         visual.viya.sas ($VisualServicesIP)
       Programming Services:
         prog.viya.sas ($ProgrammingServicesIP)
       Stateful Services:
         stateful.viya.sas ($StatefulServicesIP)
       CAS Controller:
         controller.viya.sas ($CASControllerIP)
EOF

if [ -n "${CASWorker1IP}" ]; then echo -e "       CAS Worker 1:\n         worker1.viya.sas (${CASWorker1IP})" >> "$OUTFILE"; fi
if [ -n "${CASWorker2IP}" ]; then echo -e "       CAS Worker 2:\n         worker2.viya.sas (${CASWorker2IP})" >> "$OUTFILE"; fi
if [ -n "${CASWorker3IP}" ]; then echo -e "       CAS Worker 3:\n         worker3.viya.sas (${CASWorker3IP})" >> "$OUTFILE"; fi

}

create_success_message () {

if [ -z "{{DomainName}}" ]; then
  ID=$(aws cloudformation describe-stack-resources --region "{{AWSRegion}}" --stack-name "{{CloudFormationStack}}" --logical-resource-id ElasticLoadBalancer --query StackResources[*].PhysicalResourceId --output text)
  DomainName=$(aws elb describe-load-balancers --region  "{{AWSRegion}}" --load-balancer-name "$ID" --query LoadBalancerDescriptions[*].DNSName --output text)
else
  DomainName="{{DomainName}}"
fi
[ -z "{{SSLCertificateARN}}" ] && PROTOCOL="http://" || PROTOCOL="https://"
SASHome="${PROTOCOL}${DomainName}/SASHome"
SASStudio="${PROTOCOL}${DomainName}/SASStudio"
CASMonitor="${PROTOCOL}${DomainName}/cas-shared-default-http/tkcas.dsp"


OUTFILE="$MSGDIR/sns_success_message.txt"
cat <<EOF > "$OUTFILE"

   SAS Viya Deployment for Stack "{{CloudFormationStack}}" completed successfully.

   Log into SAS Viya at $SASHome

   Log into SAS Studio at $SASStudio

   Log into CAS Server Monitor at $CASMonitor

   For administrative tasks:

     See the deployment and application logs at {{CloudWatchLogs}}

     Log into the Ansible Controller VM with the private key for KeyPair "{{KeyPairName}}":

       ssh -i /path/to/private/key.pem ec2-user@{{AnsibleControllerIP}}

     From the ansible controller, you can ssh into these VMs:

       Visual Services:
         visual.viya.sas ($VisualServicesIP)
       Programming Services:
         prog.viya.sas ($ProgrammingServicesIP)
       Stateful Services:
         stateful.viya.sas ($StatefulServicesIP)
       CAS Controller:
         controller.viya.sas ($CASControllerIP)
EOF

if [ -n "${CASWorker1IP}" ]; then echo -e "       CAS Worker 1:\n         worker1.viya.sas (${CASWorker1IP})" >> "$OUTFILE"; fi
if [ -n "${CASWorker2IP}" ]; then echo -e "       CAS Worker 2:\n         worker2.viya.sas (${CASWorker2IP})" >> "$OUTFILE"; fi
if [ -n "${CASWorker3IP}" ]; then echo -e "       CAS Worker 3:\n         worker3.viya.sas (${CASWorker3IP})" >> "$OUTFILE"; fi

# append licensing message is it exists
if [ -e "$MSGDIR/sns_license_warning_message.txt" ]; then
  cat "$MSGDIR/sns_license_warning_message.txt" >> "$OUTFILE"
fi

}

create_failure_message ( ) {

cat <<EOF > "$MSGDIR/sns_failure_message.txt"

   SAS Viya Deployment for Stack "{{CloudFormationStack}}" failed with RC=$1.

   Check the deployment logs at {{CloudWatchLogs}}.

EOF

}




cleanup () {

  RC=$?

  if [ -n "{{SNSTopic}}" ]; then

    if [[ $RC == 0 ]]; then

      # create and send success email

      create_success_message

      aws --region "{{AWSRegion}}" sns publish --topic-arn "{{SNSTopic}}" \
          --subject "SAS Viya Deployment {{CloudFormationStack}} completed." \
          --message "file://$MSGDIR/sns_success_message.txt"

    else

      # create and send failure email

      create_failure_message $RC

      aws --region "{{AWSRegion}}" sns publish --topic-arn "{{SNSTopic}}" \
          --subject "SAS Viya Deployment {{CloudFormationStack}} failed." \
          --message "file://$MSGDIR/sns_failure_message.txt"

    fi

  fi

}


# create and key and make available via SSM parameter store
echo -e y | ssh-keygen -t rsa -q -f ~/.ssh/id_rsa -N ""

KEY=$(cat ~/.ssh/id_rsa.pub)
aws ssm put-parameter --region "{{AWSRegion}}" --name "viya-ansiblekey-{{CloudFormationStack}}" --type String --value "$KEY" --overwrite

## make sure the other VMs are all up
STATUS="status"
let NUMNODES=4
while ! [ "$NUMNODES"  -eq "$(echo "$STATUS" | grep "CREATE_COMPLETE" | wc -w)" ]; do
  sleep 3
  STATUS=$(aws cloudformation describe-stack-resources --no-paginate --region "{{AWSRegion}}" --stack-name "{{CloudFormationStack}}"  --output json --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId != `AnsibleController`].ResourceStatus' --output text)
  if [ "$(echo "$STATUS" | grep "CREATE_FAILED")" ]; then exit 1; fi
done

ID=$(aws cloudformation describe-stack-resources --region  "{{AWSRegion}}" --stack-name "{{CloudFormationStack}}" --logical-resource-id VisualServices --query StackResources[*].PhysicalResourceId --output text)
VisualServicesIP=$(aws ec2 describe-instances --region  "{{AWSRegion}}" --instance-id "$ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text)

ID=$(aws cloudformation describe-stack-resources --region "{{AWSRegion}}" --stack-name "{{CloudFormationStack}}" --logical-resource-id ProgrammingServices --query StackResources[*].PhysicalResourceId --output text)
ProgrammingServicesIP=$(aws ec2 describe-instances --region  "{{AWSRegion}}" --instance-id "$ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text)

ID=$(aws cloudformation describe-stack-resources --region "{{AWSRegion}}" --stack-name "{{CloudFormationStack}}" --logical-resource-id StatefulServices --query StackResources[*].PhysicalResourceId --output text)
StatefulServicesIP=$(aws ec2 describe-instances --region  "{{AWSRegion}}" --instance-id "$ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text)

ID=$(aws cloudformation describe-stack-resources --region "{{AWSRegion}}" --stack-name "{{CloudFormationStack}}" --logical-resource-id CASController --query StackResources[*].PhysicalResourceId --output text)
CASControllerIP=$(aws ec2 describe-instances --region  "{{AWSRegion}}" --instance-id "$ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text)

if [[ "{{NumWorkers}}" -gt "0" ]]; then

  # get id work worker substack
  WorkerStackID=$(aws cloudformation describe-stack-resources --region "{{AWSRegion}}" --stack-name "{{CloudFormationStack}}" --logical-resource-id WorkerStack --query StackResources[*].PhysicalResourceId --output text)

  STATUS="status"
  while ! [ "{{NumWorkers}}"  -eq "$(echo "$STATUS" | grep "CREATE_COMPLETE" | wc -w)" ]; do
    sleep 3
    STATUS=$(aws cloudformation describe-stack-resources --no-paginate --region "{{AWSRegion}}" --stack-name "$WorkerStackID"  --output json --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId != `AnsibleController`].ResourceStatus' --output text)
    if [ "$(echo "$STATUS" | grep "CREATE_FAILED")" ]; then exit 1; fi
  done


  if [ {{NumWorkers}} -ge 1 ]; then
    # get worker sub stack id
    ID=$(aws cloudformation describe-stack-resources --region "{{AWSRegion}}" --stack-name "$WorkerStackID" --logical-resource-id CASWorker1 --query StackResources[*].PhysicalResourceId --output text)
    if [ -n "$ID" ]; then CASWorker1IP=$(aws ec2 describe-instances --region  "{{AWSRegion}}" --instance-id "$ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text); fi
  fi
  if [ {{NumWorkers}} -ge 2 ]; then
    ID=$(aws cloudformation describe-stack-resources --region "{{AWSRegion}}" --stack-name "$WorkerStackID" --logical-resource-id CASWorker2 --query StackResources[*].PhysicalResourceId --output text)
    if [ -n "$ID" ]; then CASWorker2IP=$(aws ec2 describe-instances --region  "{{AWSRegion}}" --instance-id "$ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text); fi
  fi
  if [ {{NumWorkers}} -ge 3 ]; then
    ID=$(aws cloudformation describe-stack-resources --region "{{AWSRegion}}" --stack-name "$WorkerStackID" --logical-resource-id CASWorker3 --query StackResources[*].PhysicalResourceId --output text)
    if [ -n "$ID" ]; then CASWorker3IP=$(aws ec2 describe-instances --region  "{{AWSRegion}}" --instance-id "$ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text); fi
  fi

fi

if [ -n "{{SNSTopic}}" ]; then

  # create and send start email

  create_start_message

  aws --region "{{AWSRegion}}" sns publish --topic-arn "{{SNSTopic}}" \
      --subject "Starting SAS Viya Deployment {{CloudFormationStack}}" \
      --message "file://$MSGDIR/sns_start_message.txt"

fi


# sometimes there are ssh connection errors (53) during the install
# this function allows to retry N times
function try () {
  # allow up to N attempts of a command
  # syntax: try N [command]
  RC=1; count=1; max_count=$1; shift
  until  [ $count -gt "$max_count" ]
  do
    "$@" && RC=0 && break || let count=count+1
  done
  return $RC
}




# prepare host list for ansible inventory.ini file
{
  echo visual ansible_host="$VisualServicesIP"
  echo prog ansible_host="$ProgrammingServicesIP"
  echo stateful ansible_host="$StatefulServicesIP"
  echo controller ansible_host="$CASControllerIP"
  if [ -n "${CASWorker1IP}" ]; then echo worker1 ansible_host="${CASWorker1IP}"; fi
  if [ -n "${CASWorker2IP}" ]; then echo worker2 ansible_host="${CASWorker2IP}"; fi
  if [ -n "${CASWorker3IP}" ]; then echo worker3 ansible_host="${CASWorker3IP}"; fi
} > /tmp/inventory.head

# prepare list host entries for /etc/hosts
{
  echo "$VisualServicesIP visual.viya.sas visual"
  echo "$ProgrammingServicesIP prog.viya.sas prog"
  echo "$StatefulServicesIP stateful.viya.sas stateful"
  echo "$CASControllerIP controller.viya.sas controller"
  if [ -n "${CASWorker1IP}" ]; then echo "${CASWorker1IP} worker1.viya.sas worker1"; fi
  if [ -n "${CASWorker2IP}" ]; then echo "${CASWorker2IP} worker2.viya.sas worker2"; fi
  if [ -n "${CASWorker3IP}" ]; then echo "${CASWorker3IP} worker3.viya.sas worker3"; fi
} > /tmp/hostnames.txt






install_openldap () {
  # set up OpenLDAP
  pushd ~/openldap

    # set log file
    export ANSIBLE_LOG_PATH=$LOGDIR/deployment-openldap.log

    # add hosts
    ansible-playbook update.inventory.yml

    # openldap and sssd setup
    ansible-playbook openldapsetup.yml -e "OLCROOTPW={{SASAdminPass}} OLCUSERPW={{SASUserPass}}"

  popd
}



# set log file for pre deployment steps
export PREDEPLOG="$LOGDIR/deployment-commands.log"
touch "$PREDEPLOG"

# get sas-orchestration cli
echo "$(date) Download and extract sas-orchestration cli" >> "$PREDEPLOG"
curl -Os https://support.sas.com/installation/viya/sas-orchestration-cli/lax/sas-orchestration.tgz 2>> "$PREDEPLOG"
tar xf sas-orchestration.tgz 2>> "$PREDEPLOG"
rm sas-orchestration.tgz

# build playbook
echo " " >> "$PREDEPLOG"
echo "$(date) Build ansible playbook tar file" >> "$PREDEPLOG"
./sas-orchestration build --input  /tmp/SAS_Viya_deployment_data.zip 2>> "$PREDEPLOG"

# untar playbook
echo " " >> "$PREDEPLOG"
echo "$(date) Untar ansible playbook" >> "$PREDEPLOG"
tar xf SAS_Viya_playbook.tgz 2>> "$PREDEPLOG"
rm SAS_Viya_playbook.tgz

pushd sas_viya_playbook

  # copy additional playbooks and ansible configuration file
  chmod +w ansible.cfg
  cp /tmp/ansible.* .


  echo " " >> "$PREDEPLOG"
  echo "$(date) Start Pre-Deployment tasks (see deployment-pre.log)" >> "$PREDEPLOG"

  # set log file for pre deployment steps
  export ANSIBLE_LOG_PATH="$LOGDIR/deployment-pre.log"

  # add hosts to inventory
  ansible-playbook ansible.update.inventory.yml

  # set hostnames
  ansible-playbook ansible.pre.deployment.yml

  # set prereqs on hosts
  echo " " >> "$PREDEPLOG"
  echo "$(date) Download and execute Viya Infrastructure Resource Kit (VIRK)" >> "$PREDEPLOG"
  git clone -q https://github.com/sassoftware/virk.git 2>> "$PREDEPLOG"
  ansible-playbook virk/playbooks/pre-install-playbook/viya_pre_install_playbook.yml -e 'use_pause=false'


  echo " " >> "$PREDEPLOG"
  echo "$(date) Install and set up OpenLDAP (see deployment-openldap.log)" >> "$PREDEPLOG"
  install_openldap

  #
  # main deployment
  #

  echo " " >> "$PREDEPLOG"
  echo "$(date) Start Main Deployment (see deployment-main.log)" >> "$PREDEPLOG"

  # get identities configuration from openldap setup
  cp ../openldap/sitedefault.yml roles/consul/files/

  # set log file for main deployment
  export ANSIBLE_LOG_PATH="$LOGDIR/deployment-main.log"

  # update vars file
  ansible-playbook ansible.update.vars.file.yml

  # main deployment
  try 3 ansible-playbook site.yml


popd

