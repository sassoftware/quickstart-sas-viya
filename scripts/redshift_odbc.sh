#!/bin/bash -e

# run as root
#http://docs.aws.amazon.com/redshift/latest/mgmt/install-odbc-driver-linux.html
# installs in the following locations
#/opt/amazon/redshiftodbc/lib/64
#/opt/amazon/redshiftodbc/ErrorMessages
#/opt/amazon/redshiftodbc/Setup

pushd /tmp
  curl https://s3.amazonaws.com/redshift-downloads/drivers/AmazonRedshiftODBC-64bit-1.3.6.1000-1.x86_64.rpm -o Redshift.rpm
  yum -y --nogpgcheck localinstall Redshift.rpm
popd

# modifies /opt/sas/viya/home/SASFoundation/cas.settings
#CAS_SETTINGS:
   #1: ODBCHOME=ODBC home directory
   #2: ODBCINI=$ODBCHOME/odbc.ini
   #3: ORACLE_HOME=Oracle home directory
   #4: JAVA_HOME=/usr/lib/jvm/jre-1.8.0
   #5: LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$ORACLE_HOME/lib:$JAVA_HOME/lib/amd64/server:$ODBCHOME/lib
#CAS_SETTINGS:
#   1: ODBCHOME=/opt/amazon/redshiftodbc
#   2: ODBCINI=$ODBCHOME/Setup/odbc.ini
#   #3: ORACLE_HOME=Oracle home directory
#   #4: JAVA_HOME=/usr/lib/jvm/jre-1.8.0
#   5: LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$ODBCHOME/lib
#

