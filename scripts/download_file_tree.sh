#!/bin/bash

# This script is part of the ansible controller preparation.
#
# It downloads script files and ansible playbook from the project store
#
# The script expects the following environment variables to be set:
#
# FILE_ROOT - the IAAS location of  the  project files (AWS default aws-quickstart/quickstart-sas-viya)
#
# This script overrrides the implementation of common/scripts/download_file_tree.sh
# That script download each file individually. That takes up to 1:30 minutes, vs. just a second when
# using "cp --recursive"


set -e

test -n $FILE_ROOT
DOWNLOAD_DIR=/sas/install
INSTALL_USER=$(whoami)
COMMON_CODE_TAG=7c7f8f888af3f9be4fcb1358ea009baec5d1129f

echo Downloading from ${FILE_ROOT} as ${INSTALL_USER}

pushd $DOWNLOAD_DIR
    set +e
    temploc="$(aws s3api get-bucket-location --bucket $(echo "${FILE_ROOT}" | cut -f1 -d"/") --output text)"
    loc_ret=$?
    if [ "$loc_ret" -ne 0 ]; then
        for region in $(aws ec2 describe-regions --region us-east-1 --output text --query "Regions[].RegionName"); do
        echo "Checking region $region"
        # temploc="$(aws s3api get-bucket-location --region ${region} --bucket $(echo "${FILE_ROOT}" | cut -f1 -d"/") --output text)"
		aws s3 --region ${region} cp \
		  --recursive s3://${FILE_ROOT} . \
		  --exclude 'templates/*' \
		  --exclude 'doc/*'  \
		  --exclude 'images/*' \
		  --exclude '*file_tree*' \
		  --exclude '*/README.md' \
		  --exclude '*/.*' \
		  --exclude 'ci/*'
        loc_ret=$?
        if [ "$loc_ret" -eq 0 ]; then
            break
        fi
        done
	else
		loc="${temploc/None/us-east-1}"
		set -e
	   aws s3 --region ${loc} cp \
		  --recursive s3://${FILE_ROOT} . \
		  --exclude 'templates/*' \
		  --exclude 'doc/*'  \
		  --exclude 'images/*' \
		  --exclude '*file_tree*' \
		  --exclude '*/README.md' \
		  --exclude '*/.*' \
		  --exclude 'ci/*'
    fi
    set -e

   # delete files that were uploaded earlier via cfn-init
   rm -f scripts/cloudwatch.ansiblecontroller.conf
   rm -f scripts/bastion_bootstrap.sh

   # delete cas recovery script if not applicable
   if [[ "{{CASInstanceSize}}" =~ ^r ]]; then
     rm -f scripts/recover_cascontroller.sh
   fi

   # get common code

   ##
    ## get Common Code
    ##
    RETRIES=10
    DELAY=10
    COUNT=1
    set +e
    while [ $COUNT -lt $RETRIES ]; do
      git clone https://github.com/sassoftware/quickstart-sas-viya-common.git "common"
      ret=$?
      if [ $ret -eq 0 ]; then
        RETRIES=0
        break
      fi
      rm -rf "common"
      let COUNT=$COUNT+1
      sleep $DELAY
    done
    if [ $ret -ne 0 ]; then
      exit $ret
    fi
    set -e
    pushd "common"
    git checkout $COMMON_CODE_TAG
    set +e
    git checkout -b $COMMON_CODE_TAG
    set -e
    rm -rf .git* && popd

#   git clone https://github.com/sassoftware/quickstart-sas-viya-common.git common
#   pushd common &&  git checkout $COMMON_CODE_TAG -b $COMMON_CODE_TAG && rm -rf .git* && popd


   #
   # set file permissions
   #
   # set owner
   chown -R ${INSTALL_USER}:${INSTALL_USER} .
   # set default rw-r--r--
   DIRS="scripts bin ansible common"
   find $DIRS -type d | xargs chmod 700
   find $DIRS -type f | xargs chmod 600
   # make all scripts files executable and for owner only
   find $DIRS -name "*.sh" | xargs chmod 700


popd




