#!/bin/bash

#
# process overrides
#
# Allow for overrides of common code and orchestration CLI URLs. This is most useful for testing
# common code and orchestration changes that are not yet in production.
#
# To override the common code URL:
#    Add a file named "common_code.sh" to the root S3 folder containing the quickstart.
#    This file should have a single line of the form:
#
#       COMMON_CODE_BRANCH=<git branch name>
#
#    Where <git branch name> is the name of the branch in the GitHub common code repository to be used
#    by the deployment.
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
pushd /sas/install
COMMON_CODE_OVERRIDE="common_code.sh"
if [ -f "$COMMON_CODE_OVERRIDE" ]; then
    source "$COMMON_CODE_OVERRIDE"
    if [[ -n $COMMON_CODE_BRANCH ]]; then
	rm -Rf common
	git clone https://github.com/sassoftware/quickstart-sas-viya-common.git common
	pushd common &&  git checkout $COMMON_CODE_BRANCH && rm -rf .git* && popd
	RC=$?

	if [ ! $RC = 0 ]; then
	    echo "ERROR: Common code branch $COMMON_CODE_BRANCH cannot be checked out"
	    exit $RC
	fi
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
fi
popd
