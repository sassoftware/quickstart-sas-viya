#!/bin/bash -e

## wait for the drive
while [ ! -e /dev/xvdg ]; do echo waiting for /dev/xvdg to attach; sleep 10; done
mkfs.xfs -f /dev/xvdg
mkdir -p /opt/sas
echo '/dev/xvdg      /opt/sas   xfs    defaults,nofail        0       2' >> /etc/fstab
mount /opt/sas



