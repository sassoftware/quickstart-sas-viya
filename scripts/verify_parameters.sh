#!/bin/bash

EC2_AVAIL_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
EC2_REGION=$(echo ${EC2_AVAIL_ZONE}  | sed "s/[a-z]$//")

#
# verify SSL certificate is valid, if specified
#
if [ -n "{{SSLCertificateARN}}" ]; then

  # Check the ARN to determine if this is an iam or acm certificate
  CERT_ARN="{{SSLCertificateARN}}"
  if [[ $CERT_ARN = *":iam:"* ]]; then
      # iam certificate uses get-server-certificate
      CERT_NAME=${CERT_ARN##*/}
      aws --no-paginate --region "$EC2_REGION" iam get-server-certificate --server-certificate-name "$CERT_NAME"
      RC=$?
  else
      # acm certificate uses describe-certificate
      aws --no-paginate --region "$EC2_REGION" acm describe-certificate --certificate "$CERT_ARN"
      RC=$?
  fi

  if [ ! $RC = 0 ]; then
    echo "ERROR: SSL Certificate {{SSLCertificateARN}} does not exist in the current AWS account."
  fi
  exit $RC
fi

##
## make sure the Hosted Zone is good
##
#echo "Verifying Hosted Zone Id" >> "$CMDLOG"
#if [ -n "{{HostedZoneID}}" ]; then
# # this fails the script if the HostedZoneID is invalid
# FAILMSG="ERROR: Hosted Zone {{HostedZoneID}} does not exist in the current AWS account."
# aws --no-paginate --region "{{AWSRegion}}" route53 get-hosted-zone --id {{HostedZoneID}}
# FAILMSG=
#
# # compare DNS entry used in the hosted zone with the given DNSName
# HZDNS=$(aws --no-paginate --region "{{AWSRegion}}" route53 list-resource-record-sets --hosted-zone-id {{HostedZoneID}} --query 'ResourceRecordSets[?Type==`NS`].Name' --output text)
# # fail the script if the specified DomainName does not match the hosted zone
# FAILMSG="ERROR: Value for DomainName=\"{{DomainName}}\" does not match domain \"${HZDNS:0:-1}\" in Hosted Zone {{HostedZoneID}}"
# [[ "$HZDNS" == "{{DomainName}}." ]]
# FAILMSG=
#fi
#
#
##
## verify mirror is valid
##
#
## For s3:// : lowercase initial s, remove trailing slash if it exists
#DM=$(echo -n {{DeploymentMirror}} | sed "s/^S/s/" | sed "s+/$++"   )
#if [[ $(echo -n "{{DeploymentMirror}}" | cut -c1-2 | tr [:lower:] [:upper:]) == S3 ]]; then
#  FAILMSG="ERROR: DeploymentMirror location {{DeploymentMirror}} not valid or not accessible."
#  aws s3 ls ${DM}/entitlements.json
#  FAILMSG=
#elif [[ $(echo -n "{{DeploymentMirror}}" | cut -c1-4 | tr [:lower:] [:upper:]) == HTTP ]]; then
#  FAILMSG="ERROR: DeploymentMirror location {{DeploymentMirror}} not valid or not accessible."
#  curl -L ${DM}/entitlements.json
#  FAILMSG=
#fi
#
##
## pre-deployment steps
##
#
