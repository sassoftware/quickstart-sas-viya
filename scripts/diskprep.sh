#!/bin/bash -e

DEVICE="/dev/xvdg"
DIR="/opt/sas"
mkdir -p $DIR
# wait for the drive
while [ ! -e $DEVICE ]; do echo waiting for $DEVICE to attach; sleep 10; done
# format if needed
[ "$(blkid $DEVICE | grep ext4)" = "" ] && mkfs.ext4 $DEVICE
# add to fstab is needed and mount
FSTAB="$DEVICE      $DIR   ext4    defaults,nofail        0       2"
! (grep "$FSTAB" /etc/fstab) &&  echo "$FSTAB" | tee -a /etc/fstab
mount $DIR


DEVICE="/dev/nvme0n1"   # for i3 flavors
DIR="/sastmp"
mkdir - p $DIR
# wait for the drive
while [ ! -e $DEVICE ]; do echo waiting for $DEVICE to attach; sleep 10; done
# format if needed
[ "$(blkid $DEVICE | grep ext4)" = "" ] && mkfs.ext4 -E nodiscard $DEVICE
# add to fstab is needed and mount
FSTAB="$DEVICE $DIR ext4 defaults,nofail,discard 0 2"
! (grep "$FSTAB" /etc/fstab) &&  echo "$FSTAB" | tee -a /etc/fstab
mount $DIR

mkdir ${DIR}/cascache
mkdir ${DIR}/saswork

