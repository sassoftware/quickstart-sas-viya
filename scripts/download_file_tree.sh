#!/bin/bash

# This script is part of the ansible controller preparation.
#
# It downloads script files and ansible playbook from the project store
#
# The script expects the following environment variables to be set:
#
# S3_FILE_ROOT - the s3 bucket and path with the project files (default aws-quickstart/quickstart-sas-viya)
#
# The script expects the file /tmp/tree_file.txt with one line for each file, in the form
# <relative path name>|permissions
# e.g.
# openldap/update.inventory.yml|755
#
# Note: that file is being created by common/scripts/make_file_tree.sh

set -e

test -n $S3_FILE_ROOT
TREE_FILE=/tmp/file_tree.txt
DOWNLOAD_DIR=/sas/install
INSTALL_USER=$(whoami)

# recurse the directory tree and set permissions on each level
set_directory_permission () {

  # retrieve the directory from the filename
  directory=$(dirname $1)

  # make sure the directory exists
  sudo mkdir -p $directory

  # set the ownership
  sudo chown ${INSTALL_USER}:${INSTALL_USER} $directory

  if [ ! $directory == . ]; then
    set_directory_permission $directory
  fi

}

echo Downloading from ${S3_FILE_ROOT} as ${INSTALL_USER}

pushd $DOWNLOAD_DIR
    #
    # loop over file tree
    #
    while read line; do
        # retrieve the file name
        file_name="$(echo "$line" | cut -f1 -d'|')"

        set_directory_permission $file_name

        # download the file
        aws s3 cp s3://${S3_FILE_ROOT}$file_name $file_name

        # retrieve the permissions attribute
        # and set permissions and ownership
        chmod_attr="$(echo "$line" | cut -f2 -d'|')"
        chmod $chmod_attr $file_name
        chown ${INSTALL_USER}:${INSTALL_USER} $file_name

    done < ${TREE_FILE}

    # merge the "common" file structure into the top level
#    cp -r common/* .
#    rm -rf common

popd



