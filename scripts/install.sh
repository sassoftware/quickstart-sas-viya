#!/bin/bash -e

echo VIYA_SERVICES_NODE_IP=$VIYA_SERVICES_NODE_IP

# prepate inventory.ini header
echo deployTarget ansible_ssh_host=$VIYA_SERVICES_NODE_IP > /tmp/stackinv.ini

# untar playbook
tar xvf /tmp/SAS_Viya_playbook.tgz

pushd sas_viya_playbook

  # copy additional playbooks
  mv /tmp/ansible*.yml .


  ansible-playbook ansible.update.inventory.yml

  ansible-playbook ansible.pre.deployment.yml

  ansible-playbook site.yml

popd

