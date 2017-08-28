#!/bin/bash -e

echo VIYA_SERVICES_NODE_IP=$VIYA_SERVICES_NODE_IP
echo CAS_CONTROLLER_NODE_IP=$CAS_CONTROLLER_NODE_IP


# prepate inventory.ini header
echo deployTarget ansible_ssh_host=$VIYA_SERVICES_NODE_IP > /tmp/stackinv.ini
echo controller ansible_ssh_host=$CAS_CONTROLLER_NODE_IP >> /tmp/stackinv.ini

# untar playbook
tar xf /tmp/SAS_Viya_playbook.tgz

pushd sas_viya_playbook

  # link deployment log file into web server
  touch deployment.log
  sudo ln deployment.log /var/www/html/status/deployment.log

  # copy additional playbooks
  mv /tmp/ansible.* .

  ansible-playbook ansible.update.inventory.yml

  ansible-playbook ansible.pre.deployment.yml

  ansible-playbook ansible.update.vars.file.yml

  ansible-playbook site.yml

  ansible-playbook ansible.post.deployment.yml

popd

