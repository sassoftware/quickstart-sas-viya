#!/bin/bash -e

# This is a mustache template.
# Make sure all the input parms are set
test -n "{{AWSRegion}}"
test -n "{{CloudFormationStack}}"

# sometimes there are ssh connection errors (53) during the install
# this function allows to retry N times
function try () {
  # allow up to N attempts of a command
  # syntax: try N [command]
  RC=1
  count=1; max_count=$1; shift
  until  [ $count -gt "$max_count" ]
  do
    "$@" && RC=0 && break
    let count=count+1
  done
  return $RC
}


#
#  Set up cloudwatch logging
#

# create config file - update later in post deployment
echo "[general]" > /tmp/cloudwatch.conf
chmod 440 /tmp/cloudwatch.conf

try 2 curl https://s3.amazonaws.com/aws-cloudwatch/downloads/latest/awslogs-agent-setup.py -o /tmp/awslogs-agent-setup.py

python /tmp/awslogs-agent-setup.py --region "{{AWSRegion}}" -n -c /tmp/cloudwatch.conf

# create crontab to make sure the awslog service restarts after each file rollover
# (i.e. after midnight, which is the default in the viya log configurations)
cat <<EOF > /tmp/crontab.txt
15 00 * * * service awslogs restart
EOF
# start crontab
crontab /tmp/crontab.txt


#
# get ansible public key
#
KEY=dummy
# wait until the key is available (the ansible controller puts it there)
until [ ! "$KEY" = "dummy" ]; do
   KEY=$(/var/awslogs/bin/aws ssm get-parameter --region "{{AWSRegion}}" --name "viya-ansiblekey-{{CloudFormationStack}}" --query Parameter.Value --output text)
   sleep 1
done
echo "$KEY" | su ec2-user bash -c 'tee -a ~/.ssh/authorized_keys'