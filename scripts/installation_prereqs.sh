#!/bin/bash -e

echo VIYA_SERVICES_NODE_IP=$VIYA_SERVICES_NODE_IP

install_java () {
   echo Install java 1.8
   sudo yum -y install java-1.8.0
}

check_java () {
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
}

install_ansible () {
  if ! [ type -p ansible ]; then
     # install Ansible
     /usr/local/bin/pip install 'ansible==2.2.1.0'
  fi
}

prepare_hosts_file () {
   echo deployTarget ansible_ssh_host=$VIYA_SERVICES_NODE_IP > /tmp/stackinv.ini
}

check_java
install_ansible
prepare_hosts_file

