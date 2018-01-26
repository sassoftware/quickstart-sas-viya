#!/bin/bash -e

# determine the device naming scheme (xvd vs sd)
root_drive=$(df -h | grep -v grep | awk 'NR==2{print $1}')
if [ "${root_drive:0:8}" == "/dev/xvd" ]; then
  echo "Detected 'xvd' drive naming scheme (root: $root_drive)"
  DRIVE_SCHEME='xvd'
else
  echo "Detected 'sd' drive naming scheme (root: $root_drive)"
  DRIVE_SCHEME='sd'
fi

mount_drive () {

  if [ -b "$DEVICE_PATH" ] ; then
    # create if needed
    mkdir -p $DIR
    # format if needed
    [ "$(blkid $DEVICE_PATH | grep xfs)" = "" ] && mkfs.xfs $DEVICE_PATH
    # add to fstab if needed and mount
    FSTAB="$DEVICE_PATH      $DIR   xfs    defaults,nofail        0       2"
    ! (grep "$FSTAB" /etc/fstab) &&  echo "$FSTAB" | tee -a /etc/fstab
    umount $DIR || true
    mount $DIR
  fi

}

# mount the xxxg device to /opt/sas
DIR="/opt/sas"
DEVICE_PATH="/dev/${DRIVE_SCHEME}g"
mount_drive

# mount the xxxd device to /sastmp
DIR="/sastmp"
DEVICE_PATH="/dev/${DRIVE_SCHEME}d"
mount_drive

# mount the xxxl device to /opt/sas/viya/config/data/cas (on the controller)
DIR="/opt/sas/viya/config/data/cas"
DEVICE_PATH="/dev/${DRIVE_SCHEME}l"
mount_drive

# mount the xxxh device to /home (on the prog node)
DIR="/home"
DEVICE_PATH="/dev/${DRIVE_SCHEME}h"
mount_drive



# TODO: optional additional EBS library/caslib


# set the ephemeral drive setup as service (so it can run at reboot/restart)
cat <<EOF | sudo tee  /etc/systemd/system/disks_ephemeral.service
[Unit]
Description=Format and Mount Ephemeral Disks

[Service]
ExecStart=/usr/sbin/disks_ephemeral.sh

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable disks_ephemeral.service
sudo systemctl start disks_ephemeral.service