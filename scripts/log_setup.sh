#!/bin/bash -e

# This is a mustache template.
# Make sure all the input parms are set
test -n "{{AWSRegion}}"

curl https://s3.amazonaws.com/aws-cloudwatch/downloads/latest/awslogs-agent-setup.py -o /tmp/awslogs-agent-setup.py
python /tmp/awslogs-agent-setup.py --region {{AWSRegion}} -n -c /tmp/cloudwatch.conf




