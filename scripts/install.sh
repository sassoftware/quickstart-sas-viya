#!/bin/bash

set -o pipefail
set -o errexit
set -o nounset

echo VIYA_SERVICES_NODE_IP=$VIYA_SERVICES_NODE_IP
echo CAS_CONTROLLER_NODE_IP=$CAS_CONTROLLER_NODE_IP

# sometimes there are download failures during the install
try () {
  # allow up to N attempts of a command
  # syntax: try N [command]

  max_count=$1
  shift
  count=1
  until  $@  || [ $count -gt $max_count  ]
  do
    let count=count+1
  done
}


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

  try 3 ansible-playbook ansible.pre.deployment.yml

  ansible-playbook ansible.update.vars.file.yml

  cp ../openldap/sitedefault.yml roles/consul/files/

  try 3 ansible-playbook site.yml

  ansible-playbook ansible.post.deployment.yml -e "sasboot_pw=$SASBOOT_PW"

popd

