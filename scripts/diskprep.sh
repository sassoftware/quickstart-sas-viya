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

# mount the xxxg device to /opt/sas
dir="/opt/sas"
mkdir -p $dir
device_path="/dev/${DRIVE_SCHEME}g"
if [ -b "$device_path" ] ; then
  # format if needed
  [ "$(blkid $device_path | grep xfs)" = "" ] && mkfs.xfs $device_path
  # add to fstab if needed and mount
  FSTAB="$device_path      $dir   xfs    defaults,nofail        0       2"
  ! (grep "$FSTAB" /etc/fstab) &&  echo "$FSTAB" | tee -a /etc/fstab
  umount $dir || true
  mount $dir
fi

# mount the xxxd device to /sastmp
dir="/sastmp"
mkdir -p $dir
device_path="/dev/${DRIVE_SCHEME}d"
if [ -b "$device_path" ] ; then
  # format if needed
  [ "$(blkid $device_path | grep xfs)" = "" ] && mkfs.xfs $device_path
  # add to fstab if needed and mount
  FSTAB="$device_path      $dir   xfs    defaults,nofail        0       2"
  ! (grep "$FSTAB" /etc/fstab) &&  echo "$FSTAB" | tee -a /etc/fstab
  umount $dir || true
  mount $dir
fi



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