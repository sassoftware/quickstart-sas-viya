#!/bin/bash
set -x

# this script is expected to be run by a user with sudo privileges (typically ec2-user)

trap cleanup EXIT

set -o pipefail
set -o errexit
set -o nounset


# This is a mustache template.
# Make sure all the input parms are set
test -n "{{LogGroup}}"
test -n "{{AWSRegion}}"
test -n "{{KeyPairName}}"
test -n "{{AnsibleControllerIP}}"
test -n "{{NumWorkers}}"
test -n "{{CloudFormationStack}}"
test -n "{{CloudWatchLogs}}"
test -n "{{S3FileRoot}}"

VisualServicesIP=
ProgrammingServicesIP=
StatefulServicesIP=
CASControllerIP=
CASWorker1IP=
CASWorker2IP=
CASWorker3IP=
DomainName=
FAILMSG=

# use triple mustache to avoid url encoding
USERPASS=$(echo -n '{{{SASUserPass}}}' | base64)
ADMINPASS=$(echo -n '{{{SASAdminPass}}}' | base64)



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

OUTFILE="$MSGDIR/sns_success_message.txt"
cat <<EOF > "$OUTFILE"

   SAS Viya Deployment for Stack "{{CloudFormationStack}}" completed successfully.

   Log into SAS Viya at $SASHome

   Log into SAS Studio at $SASStudio

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


}

create_failure_message ( ) {

STACKID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stacks --stack-name "{{CloudFormationStack}}" --query Stacks[*].StackId --output text)

cat <<EOF > "$MSGDIR/sns_failure_message.txt"

   SAS Viya Deployment for Stack "{{CloudFormationStack}}" failed with RC=$1.

   ${FAILMSG}

   Check the Stack Events at https://console.aws.amazon.com/cloudformation/home?region={{AWSRegion}}#/stacks?filter=active&tab=events&stackId=${STACKID}
   and the deployment logs at {{CloudWatchLogs}}.

EOF

if [ -n "$FAILMSG" ]; then
  echo "$FAILMSG" >> $CMDLOG
fi

}

check_subject_length ( ) {
  # make sure the sns message subject does not exceed the maximum 100 chars
  if [[ ${#SUBJECT} -gt 100 ]]; then
     SUBJECT=$(printf "%s..." "$(echo -n "$SUBJECT" | cut -c1-97 )" );
  fi
}



cleanup () {

  RC=$?

  if [ -n "{{SNSTopic}}" ]; then

    if [[ $RC == 0 ]]; then

      # create and send success email

      create_success_message

      SUBJECT="SAS Viya Deployment completed for Stack {{CloudFormationStack}}"
      check_subject_length

      aws --region "{{AWSRegion}}" sns publish --topic-arn "{{SNSTopic}}" --subject "$SUBJECT" \
          --message "file://$MSGDIR/sns_success_message.txt"

    else

      # create and send failure email

      create_failure_message $RC

      SUBJECT="SAS Viya Deployment failed for Stack {{CloudFormationStack}}"
      check_subject_length

      aws --region "{{AWSRegion}}" sns publish --topic-arn "{{SNSTopic}}" --subject "$SUBJECT" \
          --message "file://$MSGDIR/sns_failure_message.txt"

    fi

  fi

}


configure_self_signed_cert () {

  # reconfigure ELB to use self-signed cert
  if ! [ -n "{{SSLCertificateARN}}" ]; then

    echo "$(date) Set self-signed SSL certificate on ELB" >> "$CMDLOG"

    # get ELB name
    ELBNAME=""
    while [[ "$ELBNAME"  == "" ]]; do
      ELBNAME=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "{{CloudFormationStack}}" --logical-resource-id ElasticLoadBalancer --query StackResources[*].PhysicalResourceId --output text)
      sleep 3
    done
    ELBDNS=$(aws --no-paginate --region "{{AWSRegion}}" elb describe-load-balancers --load-balancer-name "$ELBNAME" --query LoadBalancerDescriptions[*].DNSName --output text)

    # delete existing http listener
    aws --region "{{AWSRegion}}" elb delete-load-balancer-listeners --load-balancer-name "$ELBNAME" --load-balancer-ports 443

    # create self-signed certificate
cat <<EOF > "ssl.conf"
    [ req ]
    distinguished_name = dn
    req_extensions = san
    [ dn ]
    [ san ]
    subjectAltName          = DNS:$ELBDNS
EOF
    openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 396 -nodes -config ssl.conf -subj '/CN=*.elb.amazonaws.com'


    # import cert into IAM (this creates an AWS resource that we later need to remove)
    CERTNAME="{{CloudFormationStack}}-selfsigned-cert"
    CERTARN=$(aws --region "{{AWSRegion}}" iam upload-server-certificate --server-certificate-name "$CERTNAME" --certificate-body file://cert.pem --private-key file://key.pem --query ServerCertificateMetadata.Arn --output text)

    #  until [ -n "$(aws --no-paginate --region "{{AWSRegion}}" iam list-server-certificates --query "ServerCertificateMetadataList[?Arn=='$CERTARN'].ServerCertificateId" --output text)" ]; do
    #    sleep 1
    #  done
    #  sleep 5

    # create https listener
    until aws --region "{{AWSRegion}}" elb create-load-balancer-listeners --load-balancer-name "$ELBNAME" --listeners Protocol=HTTPS,LoadBalancerPort=443,InstanceProtocol=HTTPS,InstancePort=443,SSLCertificateId=$CERTARN 2>/dev/null
    do
      sleep 1
    done
    aws --region "{{AWSRegion}}" elb set-load-balancer-policies-of-listener --load-balancer-name "$ELBNAME" --load-balancer-port 443 --policy-names AppCookieStickinessPolicy

    #  aws --region "{{AWSRegion}}" iam delete-server-certificate --server-certificate-name "$CERTNAME"

  fi
}

install_openldap () {

  # list of files created with:
  # find openldap -type f | tail -n+1 | grep -v files.txt > openldap/files.txt

  # pull down openLDAP files
  pushd ~
    while read file; do
      aws s3 cp s3://{{S3FileRoot}}$file $file
    done </tmp/openldapfiles.txt
  popd

  # set up OpenLDAP
  pushd ~/openldap

    # set log file
    export ANSIBLE_LOG_PATH=$LOGDIR/deployment-openldap.log

    # add hosts
    ansible-playbook update.inventory.yml

    # openldap and sssd setup
    ansible-playbook openldapsetup.yml -e "OLCROOTPW='$ADMINPASS' OLCUSERPW='$USERPASS'"

  popd
}


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


#
# pre-deployment steps
#

# create a key and make available via SSM parameter store
echo -e y | ssh-keygen -t rsa -q -f ~/.ssh/id_rsa -N ""

KEY=$(cat ~/.ssh/id_rsa.pub)
aws --region "{{AWSRegion}}" ssm put-parameter --name "viya-ansiblekey-{{CloudFormationStack}}" --type String --value "$KEY" --overwrite

## make sure the other VMs are all up
STATUS="status"
let NUMNODES=4
while ! [ "$NUMNODES"  -eq "$(echo "$STATUS" | grep "CREATE_COMPLETE" | wc -w)" ]; do
  sleep 3
  STATUS=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "{{CloudFormationStack}}"  --output json --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId != `AnsibleController`].ResourceStatus' --output text)
  if [ "$(echo "$STATUS" | grep "CREATE_FAILED")" ]; then exit 1; fi
done

ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "{{CloudFormationStack}}" --logical-resource-id VisualServices --query StackResources[*].PhysicalResourceId --output text)
VisualServicesIP=$(aws ec2 --no-paginate --region "{{AWSRegion}}" describe-instances --instance-id "$ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text)

ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "{{CloudFormationStack}}" --logical-resource-id ProgrammingServices --query StackResources[*].PhysicalResourceId --output text)
ProgrammingServicesIP=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-id "$ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text)

ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "{{CloudFormationStack}}" --logical-resource-id StatefulServices --query StackResources[*].PhysicalResourceId --output text)
StatefulServicesIP=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-id "$ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text)

ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "{{CloudFormationStack}}" --logical-resource-id CASController --query StackResources[*].PhysicalResourceId --output text)
CASControllerIP=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-id "$ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text)

if [[ "{{NumWorkers}}" -gt "0" ]]; then

  # get id work worker substack
  WorkerStackID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "{{CloudFormationStack}}" --logical-resource-id WorkerStack --query StackResources[*].PhysicalResourceId --output text)

  STATUS="status"
  while ! [ "{{NumWorkers}}"  -eq "$(echo "$STATUS" | grep "CREATE_COMPLETE" | wc -w)" ]; do
    sleep 3
    STATUS=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "$WorkerStackID"  --output json --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId != `AnsibleController`].ResourceStatus' --output text)
    if [ "$(echo "$STATUS" | grep "CREATE_FAILED")" ]; then exit 1; fi
  done


  if [ {{NumWorkers}} -ge 1 ]; then
    # get worker sub stack id
    ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "$WorkerStackID" --logical-resource-id CASWorker1 --query StackResources[*].PhysicalResourceId --output text)
    if [ -n "$ID" ]; then CASWorker1IP=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-id "$ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text); fi
  fi
  if [ {{NumWorkers}} -ge 2 ]; then
    ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "$WorkerStackID" --logical-resource-id CASWorker2 --query StackResources[*].PhysicalResourceId --output text)
    if [ -n "$ID" ]; then CASWorker2IP=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-id "$ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text); fi
  fi
  if [ {{NumWorkers}} -ge 3 ]; then
    ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "$WorkerStackID" --logical-resource-id CASWorker3 --query StackResources[*].PhysicalResourceId --output text)
    if [ -n "$ID" ]; then CASWorker3IP=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-id "$ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text); fi
  fi

fi


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


# before we start make sure the stack is still good. It could have failed in resources that are created post-VM (especially the ELB)
check_stack_status () {
  STACK_STATUS=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stacks --stack-name "{{CloudFormationStack}}"  --query Stacks[*].StackStatus --output text)
  # fail script if stack creation failed
  [[ "$STACK_STATUS" != "CREATE_FAILED" ]]
}
# make sure the ELB has been created
ELBNAME=""
while [[ "$ELBNAME"  == "" ]]; do
  ELBNAME=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "{{CloudFormationStack}}" --logical-resource-id ElasticLoadBalancer --query StackResources[*].PhysicalResourceId --output text)
  check_stack_status
  sleep 3
done

# set log file for pre deployment steps
export CMDLOG="$LOGDIR/deployment-commands.log"
touch "$CMDLOG"

# make sure the Hosted Zone is good
if [ -n "{{HostedZoneID}}" ]; then
 # this fails the script if the HostedZoneID is invalid
 FAILMSG="ERROR: Hosted Zone {{HostedZoneID}} does not exist in the current AWS account."
 aws --no-paginate --region "{{AWSRegion}}" route53 get-hosted-zone --id {{HostedZoneID}}
 FAILMSG=

 # compare DNS entry used in the hosted zone with the given DNSName
 HZDNS=$(aws --no-paginate --region "{{AWSRegion}}" route53 list-resource-record-sets --hosted-zone-id {{HostedZoneID}} --query 'ResourceRecordSets[?Type==`NS`].Name' --output text)
 # fail the script if the specified DomainName does not match the hosted zone
 FAILMSG="ERROR: Value for DomainName=\"{{DomainName}}\" does not match domain \"${HZDNS:0:-1}\" in Hosted Zone {{HostedZoneID}}"
 [[ "$HZDNS" == "{{DomainName}}." ]]
 FAILMSG=
fi

#
# Beging Viya software installation
#

if [ -z "{{DomainName}}" ]; then
  ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "{{CloudFormationStack}}" --logical-resource-id ElasticLoadBalancer --query StackResources[*].PhysicalResourceId --output text)
  DomainName=$(aws --no-paginate --region "{{AWSRegion}}" elb describe-load-balancers --load-balancer-name "$ID" --query LoadBalancerDescriptions[*].DNSName --output text)
else
  DomainName="{{DomainName}}"
fi

PROTOCOL="https://"
SASHome="${PROTOCOL}${DomainName}/SASHome"
SASStudio="${PROTOCOL}${DomainName}/SASStudio"




if [ -n "{{SNSTopic}}" ]; then

  # create and send start email

  create_start_message
  SUBJECT="Starting SAS Viya Deployment {{CloudFormationStack}}"
  check_subject_length

  aws --region "{{AWSRegion}}" sns publish --topic-arn "{{SNSTopic}}" --subject "$SUBJECT" \
      --message "file://$MSGDIR/sns_start_message.txt"

fi


configure_self_signed_cert

# get sas-orchestration cli
echo "$(date) Download and extract sas-orchestration cli" >> "$CMDLOG"
curl -Os https://support.sas.com/installation/viya/sas-orchestration-cli/lax/sas-orchestration.tgz 2>> "$CMDLOG"
tar xf sas-orchestration.tgz 2>> "$CMDLOG"
rm sas-orchestration.tgz

# build playbook
echo " " >> "$CMDLOG"
echo "$(date) Build ansible playbook tar file" >> "$CMDLOG"
./sas-orchestration build --input  /tmp/SAS_Viya_deployment_data.zip 2>> "$CMDLOG"

# untar playbook
echo " " >> "$CMDLOG"
echo "$(date) Untar ansible playbook" >> "$CMDLOG"
tar xf SAS_Viya_playbook.tgz 2>> "$CMDLOG"
rm SAS_Viya_playbook.tgz

pushd sas_viya_playbook

  # copy additional playbooks and ansible configuration file
  chmod +w ansible.cfg
  cp /tmp/ansible.* .

  #
  # pre deployment
  #

  echo " " >> "$CMDLOG"
  echo "$(date) Start Pre-Deployment tasks (see deployment-pre.log)" >> "$CMDLOG"

  # set log file for pre deployment steps
  export ANSIBLE_LOG_PATH="$LOGDIR/deployment-pre.log"

  # add hosts to inventory
  ansible-playbook ansible.update.inventory.yml

  # set hostnames
  ansible-playbook ansible.pre.deployment.yml

  # set prereqs on hosts
  echo " " >> "$CMDLOG"
  echo "$(date) Download and execute Viya Infrastructure Resource Kit (VIRK)" >> "$CMDLOG"
  git clone -q https://github.com/sassoftware/virk.git 2>> "$CMDLOG"
  git --git-dir virk/.git checkout viya-3.3 2>> "$CMDLOG"
  ansible-playbook virk/playbooks/pre-install-playbook/viya_pre_install_playbook.yml -e 'use_pause=false'

  if [ -n "$USERPASS" ]; then
    echo " " >> "$CMDLOG"
    echo "$(date) Install and set up OpenLDAP (see deployment-openldap.log)" >> "$CMDLOG"
    install_openldap
  fi

  #
  # main deployment
  #

  echo " " >> "$CMDLOG"
  echo "$(date) Start Main Deployment (see deployment-main.log)" >> "$CMDLOG"

  # get identities configuration from openldap setup
  if [ -n "$USERPASS" ]; then
    cp ../openldap/sitedefault.yml roles/consul/files/
  fi

  # set log file for main deployment
  export ANSIBLE_LOG_PATH="$LOGDIR/deployment-main.log"

  # update vars file
  ansible-playbook ansible.update.config.yml


  # main deployment
  try 3 ansible-playbook site.yml

  #
  # post deployment
  #

  # reset sasboot
  echo " " >> "$CMDLOG"
  echo "$(date) Reset sasboot password (see deployment-post.log)" >> "$CMDLOG"

  # set log file for post deployment steps  # set log file for pre deployment steps
  export ANSIBLE_LOG_PATH="$LOGDIR/deployment-post.log"

  ansible-playbook ansible.post.deployment.yml -e "sasboot_pw='$ADMINPASS'" -e "cas_virtual_host='$DomainName'" --tags "sasboot, backups, cas"

popd

