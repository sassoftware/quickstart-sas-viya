#!/bin/bash

# this script is expected to be run by a user with sudo privileges (typically ec2-user)

trap cleanup EXIT

set -o pipefail
set -o errexit
set -o nounset


# This is a mustache template.
# Make sure all the input parms are set
test -n "{{VisualServicesIP}}"
test -n "{{ProgrammingServicesIP}}"
test -n "{{StatefulServicesIP}}"
test -n "{{CASControllerIP}}"
test -n "{{ViyaAdminPass}}"
test -n "{{ViyaUserPass}}"
test -n "{{LogGroup}}"
test -n "{{AWSRegion}}"
test -n "{{KeyPairName}}"
test -n "{{AnsibleControllerIP}}"
test -n "{{CASNodeInstanceType}}"
test -n "{{CloudFormationStack}}"
test -n "{{CloudWatchLogs}}"
test -n "{{SASHome}}"
test -n "{{SASStudio}}"
test -n "{{CASMonitor}}"


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

       Visual Services (visual.viya.sas):
         visual ({{VisualServicesIP}})
       Programming Services (programming.viya.sas):
         programming ({{ProgrammingServicesIP}})
       Stateful Services (stateful.viya.sas):
         stateful ({{StatefulServicesIP}})
       CAS Controller (controller.viya.sas)
         controller ({{CASControllerIP}})
EOF

[ -n "{{CASWorker1IP}}" ] && echo -e "       CAS Worker 1 (worker1.viya.sas):\n         worker1 ({{CASWorker1IP}})" >> "$OUTFILE" || :
[ -n "{{CASWorker2IP}}" ] && echo -e "       CAS Worker 2 (worker2.viya.sas):\n         worker2 ({{CASWorker2IP}})" >> "$OUTFILE" || :
[ -n "{{CASWorker3IP}}" ] && echo -e "       CAS Worker 3 (worker3.viya.sas):\n         worker3 ({{CASWorker3IP}})" >> "$OUTFILE" || :
[ -n "{{CASWorker4IP}}" ] && echo -e "       CAS Worker 4 (worker4.viya.sas):\n         worker4 ({{CASWorker4IP}})" >> "$OUTFILE" || :


}

create_success_message () {

OUTFILE="$MSGDIR/sns_success_message.txt"
cat <<EOF > "$OUTFILE"

   SAS Viya Deployment for Stack "{{CloudFormationStack}}" completed successfully.

   Log into SAS Viya at {{SASHome}}

   Log into SAS Studio at {{SASStudio}}

   Log into CAS Server Monitor at {{CASMonitor}}

   For administrative tasks:

     See the deployment and application logs at {{CloudWatchLogs}}

     Log into the Ansible Controller VM with the private key for KeyPair "{{KeyPairName}}":

       ssh -i /path/to/private/key.pem ec2-user@{{AnsibleControllerIP}}

     From the ansible controller, you can ssh into these VMs:

       Visual Services (visual.viya.sas):
         visual ({{VisualServicesIP}})
       Programming Services (programming.viya.sas):
         programming ({{ProgrammingServicesIP}})
       Stateful Services (stateful.viya.sas):
         stateful ({{StatefulServicesIP}})
       CAS Controller (controller.viya.sas)
         controller ({{CASControllerIP}})
EOF

[ -n "{{CASWorker1IP}}" ] && echo -e "       CAS Worker 1 (worker1.viya.sas):\n         worker1 ({{CASWorker1IP}})" >> "$OUTFILE" || :
[ -n "{{CASWorker2IP}}" ] && echo -e "       CAS Worker 2 (worker2.viya.sas):\n         worker2 ({{CASWorker2IP}})" >> "$OUTFILE" || :
[ -n "{{CASWorker3IP}}" ] && echo -e "       CAS Worker 3 (worker3.viya.sas):\n         worker3 ({{CASWorker3IP}})" >> "$OUTFILE" || :
[ -n "{{CASWorker4IP}}" ] && echo -e "       CAS Worker 4 (worker4.viya.sas):\n         worker4 ({{CASWorker4IP}})" >> "$OUTFILE" || :

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

create_cores_warning_message ( ) {

TYPE="$1"

if [ "$TYPE" = "UNDER" ]; then


cat <<EOF > "$MSGDIR/sns_license_warning_message.txt"

  WARNING:

    Your SAS Viya license allows you to use $LICCORES cores for your CAS compute cluster.
    Your current configuration uses only $USEDCORES cores for your cluster.
    Therefore, your SAS Viya deployment is using fewer cores than the number of cores you are licensed for.

    This deployment will run but it will not use the number of licensed cores in your SAS Viya deployment.
    To use your licensed cores, you should increase your Amazon Web Services cores to match the number of licensed cores.

    Redeploy with a combination EC2 instance size (CASNodeInstanceType) and CAS worker count (NumWorkers) that matches your licensed cores.

    The number of cores for your deployment is determined by these options:

      CASNodeInstanceType: {{CASNodeInstanceType}}
      NumWorkers: $WORKERCOUNT

    These settings result in $USEDCORES provisioned cores (CAS Controller + $WORKERCOUNT CAS Worker(s)).

EOF

else

cat <<EOF > "$MSGDIR/sns_license_warning_message.txt"

  WARNING:

    Your SAS Viya license allows you to use $LICCORES cores for your CAS compute cluster.
    Your current configuration provisions $USEDCORES cores for your cluster.
    Therefore, your deployment is provisioning more cores than the number of cores you are licensed for.

    This deployment will run but the additional AWS provisioned cores will not be used and will incur expenses from Amazon Web Services.
    You should decrease your Amazon Web Services cores to match the number of licensed cores.

    Redeploy with a combination of EC2 instance size (CASNodeInstanceType) and CAS worker count (NumWorkers) that matches your licensed cores.

    The number of cores for your deployment is determined by these options:

      CASNodeInstanceType: {{CASNodeInstanceType}}
      NumWorkers: $WORKERCOUNT

    These settings result in $USEDCORES provisioned cores (CAS Controller + $WORKERCOUNT CAS Worker(s)).

EOF

fi

}




if [ -n "{{SNSTopic}}" ]; then

  # create and send start email

  create_start_message

  aws --region "{{AWSRegion}}" sns publish --topic-arn "{{SNSTopic}}" \
      --subject "Starting SAS Viya Deployment {{CloudFormationStack}}" \
      --message "file://$MSGDIR/sns_start_message.txt"

fi



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


# sometimes there are ssh connection errors (53) during the install
# this function allows to retry N times
function try () {
  # allow up to N attempts of a command
  # syntax: try N [command]

  count=1; max_count=$1; shift
  until  "$@"  || [ $count -gt "$max_count" ]; do
    let count=count+1
  done
}




# prepare host list for ansible inventory.ini file
{
  echo visual ansible_host="{{VisualServicesIP}}"
  echo programming ansible_host="{{ProgrammingServicesIP}}"
  echo stateful ansible_host="{{StatefulServicesIP}}"
  echo controller ansible_host="{{CASControllerIP}}"
  [ -n "{{CASWorker1IP}}" ] && echo worker1 ansible_host="{{CASWorker1IP}}" || :
  [ -n "{{CASWorker2IP}}" ] && echo worker2 ansible_host="{{CASWorker2IP}}" || :
  [ -n "{{CASWorker3IP}}" ] && echo worker3 ansible_host="{{CASWorker3IP}}" || :
  [ -n "{{CASWorker4IP}}" ] && echo worker4 ansible_host="{{CASWorker4IP}}" || :
} > /tmp/inventory.head

# prepare list host entries for /etc/hosts
{
  echo "{{VisualServicesIP}} visual.viya.sas visual"
  echo "{{ProgrammingServicesIP}} programming.viya.sas programming"
  echo "{{StatefulServicesIP}} stateful.viya.sas stateful"
  echo "{{CASControllerIP}} controller.viya.sas controller"
  [ -n "{{CASWorker1IP}}" ] && echo "{{CASWorker1IP}} worker1.viya.sas worker1" || :
  [ -n "{{CASWorker2IP}}" ] && echo "{{CASWorker2IP}} worker2.viya.sas worker2" || :
  [ -n "{{CASWorker3IP}}" ] && echo "{{CASWorker3IP}} worker3.viya.sas worker3" || :
  [ -n "{{CASWorker4IP}}" ] && echo "{{CASWorker4IP}} worker4.viya.sas worker4" || :
} > /tmp/hostnames.txt



## make sure the other VMs are all up
STATUS="status"
while ! [ "$(echo "$STATUS" | wc -w)"  -eq "$(echo "$STATUS" | grep "CREATE_COMPLETE" | wc -w)" ]; do
  sleep 3
  STATUS=$(aws cloudformation  describe-stack-resources --region "{{AWSRegion}}" --stack-name "{{CloudFormationStack}}"  --output json --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId != `AnsibleController`].ResourceStatus' --output text)
  [ "$(echo "$STATUS" | grep "CREATE_FAILED")" ]  && exit 1 || :
done


install_openldap () {
  # set up OpenLDAP
  pushd ~/openldap

    # set log file
    export ANSIBLE_LOG_PATH=$LOGDIR/deployment-openldap.log

    # add hosts
    ansible-playbook update.inventory.yml

    # openldap and sssd setup
    ansible-playbook openldapsetup.yml -e "OLCROOTPW={{ViyaAdminPass}} OLCUSERPW={{ViyaUserPass}}"

  popd
}


check_cores ()
{
  # number of licensed cores for CAS

  # cat,xargs,sed: create single, semicolon-terminated lines;
  UNWRAPPED=$(cat  ~/sas_viya_playbook/SASViyaV0300_*_Linux_x86-64.txt | xargs | sed 's/;/;\n/g')
  CPUNUM=$(echo "$UNWRAPPED" | grep EXPIRE | grep PRODNUM1141 | sed -r "s/.*CPU=(.*)\;/\1/")
  LICCORES=$(echo "$UNWRAPPED" | grep NAME="$CPUNUM" | sed  -r "s/.*SERIAL=\+([0-9]+).*/\1/")

  CPUCOUNT=$(ssh "{{CASControllerIP}}" cat /proc/cpuinfo | grep -c ^processor)
  let CPUCOUNT=CPUCOUNT/2

  WORKERCOUNT=$(grep -c worker /tmp/inventory.head || true)
  let CASNODESCOUNT=WORKERCOUNT+1

  let USEDCORES=CASNODESCOUNT*CPUCOUNT

  echo Licensed Cores = "$LICCORES"
  echo Used Cores = $USEDCORES

  if ! [[ $USEDCORES -eq $LICCORES ]]; then

    if [[ $USEDCORES -gt $LICCORES ]]; then
      LICCPU="OVER"
     elif [[ $USEDCORES -lt $LICCORES ]]; then
      LICCPU="UNDER"
    fi

    create_cores_warning_message "$LICCPU"

    if [ -n "{{SNSTopic}}" ]; then

      aws --region "{{AWSRegion}}" sns publish --topic-arn "{{SNSTopic}}" \
          --subject "Licensing Notification for SAS Viya Deployment {{CloudFormationStack}}" \
          --message "file://$MSGDIR/sns_license_warning_message.txt"

    fi
  fi


}

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

# location of installed cli: /opt/sas/viya/home/bin/sas-orchestration


# set log file for pre deployment steps
export PREDEPLOG="$LOGDIR/deployment-commands.log"

# build playbook
/tmp/sas-orchestration build --input  /tmp/SAS_Viya_deployment_data.zip &> "$PREDEPLOG"

# untar playbook
tar xf SAS_Viya_playbook.tgz &>> "$PREDEPLOG"
rm SAS_Viya_playbook.tgz

pushd sas_viya_playbook

  # copy additional playbooks and ansible configuration file
  chmod +w ansible.cfg
  cp /tmp/ansible.* .


  # set log file for pre deployment steps
  export ANSIBLE_LOG_PATH="$LOGDIR/deployment-pre.log"

  # add hosts to inventory
  ansible-playbook ansible.update.inventory.yml

  # set hostnames
  ansible-playbook ansible.pre.deployment.yml

  # set prereqs on hosts
  git clone https://github.com/sassoftware/virk.git &>> "$PREDEPLOG"
  ansible-playbook virk/playbooks/pre-install-playbook/viya_pre_install_playbook.yml -e 'use_pause=false'


  check_cores &>> "$PREDEPLOG"

  install_openldap

  #
  # main deployment
  #
  # get identities configuration from openldap setup
  cp ../openldap/sitedefault.yml roles/consul/files/

  # set log file for main deployment
  export ANSIBLE_LOG_PATH="$LOGDIR/deployment-main.log"

  # update vars file
  ansible-playbook ansible.update.vars.file.yml

  # main deployment
  try 2 ansible-playbook site.yml

  # Only for EA: copy the redshift resources
  ansible-playbook ansible.post.deployment.yml --tags "EA"

popd

