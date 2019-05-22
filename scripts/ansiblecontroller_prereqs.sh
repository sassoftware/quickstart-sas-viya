#!/bin/bash -e

set -x

# Run this script as install user (e.g. ec2-user on aws)

INSTALL_DIR=/sas/install
NFS_SHARE_DIR=${INSTALL_DIR}/nfs
ANSIBLE_KEY_DIR=${NFS_SHARE_DIR}/ansible_key
READINESS_FLAGS_DIR=${NFS_SHARE_DIR}/readiness_flags
LOGS_DIR=/var/log/sas/install
INSTALL_USER=$(whoami)
UTILITIES_DIR="${INSTALL_DIR}/bin"
#
# create directories
#
sudo mkdir -p ${INSTALL_DIR}
sudo chmod 755 ${INSTALL_DIR}
sudo chown ${INSTALL_USER}:${INSTALL_USER} ${INSTALL_DIR}

sudo mkdir -p ${NFS_SHARE_DIR}
sudo chmod 777 ${NFS_SHARE_DIR}  # may not need to be 777 since it should be the same user everywhere. The user may have a different UID/GUI though.
sudo chown ${INSTALL_USER}:${INSTALL_USER} ${NFS_SHARE_DIR}

sudo mkdir -p ${ANSIBLE_KEY_DIR}
sudo chmod 777 ${ANSIBLE_KEY_DIR}  # may not need to be 777 since it should be the same user everywhere. The user may have a different UID/GUI though.
sudo chown ${INSTALL_USER}:${INSTALL_USER} ${ANSIBLE_KEY_DIR}

sudo mkdir -p ${READINESS_FLAGS_DIR}
sudo chmod 777 ${READINESS_FLAGS_DIR}   # may not need to be 777 since it should be the same user everywhere. The user may have a different UID/GUI though.
sudo chown ${INSTALL_USER}:${INSTALL_USER} ${READINESS_FLAGS_DIR}

sudo mkdir -p ${LOGS_DIR}
sudo chmod 755 ${LOGS_DIR}
sudo chown ${INSTALL_USER}:${INSTALL_USER} ${LOGS_DIR}

sudo mkdir -p ${UTILITIES_DIR}
sudo chmod 755 ${UTILITIES_DIR}
sudo chown ${INSTALL_USER}:${INSTALL_USER} ${UTILITIES_DIR}

#
# Install or upgrade java to 1.8
#
install_java () {
   echo Install java 1.8
   sudo yum -y install java-1.8.0
}

if type -p java; then
    echo found java executable in PATH
    _java=java
elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
    echo found java executable in JAVA_HOME
    _java="$JAVA_HOME/bin/java"
else
    install_java
fi


if [[ "$_java" ]]; then
    version=$("$_java" -version 2>&1 | awk -F '"' '/version/ {print $2}')
    echo version "$version"
    if [[ "$version" < "1.8" ]]; then
        sudo yum -y remove java
        install_java
    else
        echo version 1.8 or greater
    fi
fi

#
# install ansible
#
if ! type -p ansible;  then
   # install Ansible
   sudo pip install 'ansible==2.7.10'
fi

#
# install git
#
if ! type -p git; then
   # install git
   sudo yum install -y git
fi

#
# NFS setup
#
echo -n "${NFS_SHARE_DIR} *(rw,sync)" | sudo tee /etc/exports
sudo yum install -y nfs-utils nfs-utils-lib

if ! type -p systemctl; then
    sudo service rpcbind start
    sudo /sbin/chkconfig --add rpcbind
    sudo service nfs start
    sudo /sbin/chkconfig --add nfs
else
    sudo systemctl start rpcbind
    sudo systemctl enable rpcbind
    sudo systemctl start nfs
    sudo systemctl enable nfs
fi


#
#  Ansible Key
#
ssh-keygen -t rsa -f ~/.ssh/id_rsa -q -N ''
cp ~/.ssh/id_rsa.pub ${ANSIBLE_KEY_DIR}/id_rsa.pub








