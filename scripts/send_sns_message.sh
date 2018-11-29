#!/bin/bash -e

if [[ -z "{{SNSTopic}}" ]]; then
  exit 0
fi

EC2_AVAIL_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
EC2_REGION=$(echo ${EC2_AVAIL_ZONE}  | sed "s/[a-z]$//")

# This is a mustache template.
# Make sure all the input parms are set
test -n {{StackName}}
test -n {{StackId}}
test -n {{CloudWatchLogs}}
test -n {{AnsibleControllerIP}}
test -n {{KeyPairName}}

# Inputs
TYPE=$1   # starting|success|failure
FRC=${RC}

#
# "Starting SAS Viya Deployment" message
#
START_SUBJECT="Starting SAS Viya Deployment {{StackName}}"
START_MESSAGE='

  Starting SAS Viya Deployment for Stack "{{StackName}}".

  Follow the deployment logs at {{CloudWatchLogs}}

  Log into the Ansible Controller VM with the private key for KeyPair "{{KeyPairName}}":

       ssh -i /path/to/private/key.pem ec2-user@{{AnsibleControllerIP}}

  From the ansible controller, you can ssh into these VMs:

       Viya Services:
         services.viya.sas (services)
       CAS Controller:
         controller.viya.sas (controller)
'

#
#  "completed successfully" message
#
SUCCESS_SUBJECT="SAS Viya Deployment completed for Stack {{StackName}}"
SUCCESS_MESSAGE='

   SAS Viya Deployment for Stack "{{StackName}}" completed successfully.

   Log into SAS Viya at {{SASDrive}}

   Log into SAS Studio at {{SASStudio}}

   For administrative tasks:

     See the deployment and application logs at {{CloudWatchLogs}}

     Log into the Ansible Controller VM with the private key for KeyPair "{{KeyPairName}}":

       ssh -i /path/to/private/key.pem ec2-user@{{AnsibleControllerIP}}

     From the ansible controller, you can ssh into these VMs:

       Viya Services:
         services.viya.sas (services)
       CAS Controller:
         controller.viya.sas (controller)
'

#
# "failed" message
#
FAILURE_SUBJECT="SAS Viya Deployment failed for Stack {{StackName}}"
FAILURE_MESSAGE="

   SAS Viya Deployment for Stack "{{StackName}}" failed with RC=$FRC.

   ${FAILMSG}

   Check the Stack Events at
   https://console.aws.amazon.com/cloudformation/home?region={{AWSRegion}}#/stacks?filter=active&tab=events&stackId={{StackId}}
   and the deployment logs at
   {{CloudWatchLogs}}.

"


if [[ $TYPE == starting ]]; then
  SUBJECT=$START_SUBJECT
  MESSAGE=$START_MESSAGE
elif [[ $TYPE == success ]]; then
  SUBJECT=$SUCCESS_SUBJECT
  MESSAGE=$SUCCESS_MESSAGE
elif [[ $TYPE == failure ]]; then
  SUBJECT=$FAILURE_SUBJECT
  MESSAGE=$FAILURE_MESSAGE
else
  exit 1
fi

#
# make sure the sns message subject does not exceed the maximum 100 chars
#
if [[ ${#SUBJECT} -gt 100 ]]; then
     SUBJECT=$(printf "%s..." "$(echo -n "$SUBJECT" | cut -c1-97 )" );
fi

aws --region "$EC2_REGION" sns publish --topic-arn "{{SNSTopic}}" --subject "$SUBJECT" --message "$MESSAGE"

