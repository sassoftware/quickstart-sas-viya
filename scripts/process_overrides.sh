#!/bin/bash

EC2_AVAIL_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
EC2_REGION=$(echo ${EC2_AVAIL_ZONE}  | sed "s/[a-z]$//")

#
# process overrides
#
# Allow for overrides of common code and orchestration CLI URLs. This is most useful for testing
# common code and orchestration changes that are not yet in production.
#
# To override the common code URL:
#    Add a file named "git_overrides.sh" to the root S3 folder containing the quickstart.
#    This file can contain the following variables have a single line of the form:
#
#       COMMON_CODE_BRANCH=<git branch name>
#       VIYA_ARK_URL=<s3 location for Viya Ark>
#
#    Where :
#       <git branch name> is the name of the branch in the GitHub common code repository to be used
#          by the deployment.
#       <s3 location for Viya Ark> is the s3 URL pointing to a Viya Ark folder in S3 (to be used when testing
#          a Viya Ark change that is not yet publicly available from GitHub)
#
# To override the SAS Orchestration CLI URL:
#    Add a file named "group_vars.yaml" to the root S3 folder containing the quickstart.
#    This file should have a single line of the form:
#
#      SAS_ORCHESTRATION_CLI_URL: "<orchestration url>"
#
#    Where <orchestration url> is a URL pointing to the sas-orchestration-linux.tgz file to be used
#    by the deployment. *This URL must be accessible to the quickstart running in the AWS cloud - i.e. it
#    can't be a location on the SAS intranet.

# Check for common code url override file - if this file exists, open it to get the correct
# common code tag
INSTALL_USER=$(whoami)

pushd /sas/install
GIT_OVERRIDE="git_overrides.sh"
if [ -f "$GIT_OVERRIDE" ]; then
    source "$GIT_OVERRIDE"
    if [[ -n $COMMON_CODE_BRANCH ]]; then
	rm -Rf common
	git clone https://github.com/sassoftware/quickstart-sas-viya-common.git common
	pushd common &&  git checkout $COMMON_CODE_BRANCH && rm -rf .git* && popd
	RC=$?

	if [ ! $RC = 0 ]; then
	    echo "ERROR: Common code branch $COMMON_CODE_BRANCH cannot be checked out"
	    exit $RC
	fi
	echo "Overriding common code branch with branch: $COMMON_CODE_BRANCH"
    fi
    if [[ -n $VIYA_ARK_URL ]]; then
	VIRK_DIR="/sas/install/ansible/sas_viya_playbook/viya-ark"
	rm -Rf $VIRK_DIR
	aws --region ${EC2_REGION} s3 sync $VIYA_ARK_URL $VIRK_DIR
	chown -R ${INSTALL_USER}:${INSTALL_USER} ansible
	
	RC=$?
	
	if [ ! $RC = 0 ]; then
	    echo "ERROR: Could not override Viya Ark with $VIYA_ARK_URL"
	    exit $RC
	fi
	echo "Overriding Viya Ark location with $VIYA_ARK_URL"
    fi
fi
   
# Check for ansible group_var override file - if this file exists, copy it to
# the common/ansible/playbooks/group_vars folder to override variables defined in
# all.yaml
GROUP_VAR_OVERRIDE="group_vars.yaml"
if [[ -f "$GROUP_VAR_OVERRIDE" ]]; then
    cp $GROUP_VAR_OVERRIDE common/ansible/playbooks/group_vars/AnsibleController.yml
    RC=$?

    if [ ! $RC = 0 ]; then
	echo "ERROR: group_vars.yaml override file cannot be processed."
	exit $RC
    fi
    echo "Overriding group vars"
fi
popd
