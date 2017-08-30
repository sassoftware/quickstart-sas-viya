#!/bin/bash -e

echo VIYA_SERVICES_NODE_IP=$VIYA_SERVICES_NODE_IP
echo CAS_CONTROLLER_NODE_IP=$CAS_CONTROLLER_NODE_IP


# prepare inventory.ini header
echo deployTarget ansible_ssh_host=$VIYA_SERVICES_NODE_IP > /tmp/inventory.head
echo controller ansible_ssh_host=$CAS_CONTROLLER_NODE_IP >> /tmp/inventory.head

# set up OpenLDAP
pushd openldap

  # link deployment log file into web server
  touch openldap-deployment.log
  sudo ln openldap-deployment.log /var/www/html/status/openldap-deployment.log

  ansible-playbook update.inventory.yml

  ansible-playbook openldapsetup.yml

popd



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

  cp ../openldap/sitedefault.yml roles/consul/files/

  ansible-playbook site.yml

  ansible-playbook ansible.post.deployment.yml

popd

