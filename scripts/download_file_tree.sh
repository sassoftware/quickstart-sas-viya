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
COMMON_CODE_TAG=6ac38f84cd6c94071a4d2c767c4f6f9f63c48907

echo Downloading from ${FILE_ROOT} as ${INSTALL_USER}

pushd $DOWNLOAD_DIR

   aws s3 cp --recursive s3://${FILE_ROOT} . \
      --exclude 'templates/*' \
      --exclude 'doc/*'  \
      --exclude 'images/*' \
      --exclude '*file_tree*' \
      --exclude '*/README.md' \
      --exclude '*/.*' \
      --exclude 'ci/*'

   # delete files that were uploaded earlier via cfn-init
   rm -f scripts/cloudwatch.ansiblecontroller.conf
   rm -f scripts/bastion_bootstrap.sh

   # delete cas recovery script if not applicable
   if [[ "{{CASInstanceType}}" =~ "^r" ]]; then
     rm -f scripts/recover_cascontroller.sh
   fi

   # get common code
   git clone https://github.com/sassoftware/quickstart-sas-viya-common.git common
   pushd common &&  git checkout $COMMON_CODE_TAG -b $COMMON_CODE_TAG && rm -rf .git* && popd


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




