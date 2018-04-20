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

# mount the xxxl device to /opt/sas/viya/config/data/cas
dir="/opt/sas/viya/config/data/cas"
mkdir -p $dir
device_path="/dev/${DRIVE_SCHEME}l"
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


# Tag ebs volumes
INSTANCE_ID=$( curl -s http://169.254.169.254/latest/meta-data/instance-id )
DISK_IDS=$(aws --region {{AWSRegion}} ec2 describe-volumes  --filter "Name=attachment.instance-id, Values=$INSTANCE_ID" --query "Volumes[].VolumeId" --out text)
aws ec2  --region {{AWSRegion}}  create-tags --resources $DISK_IDS --tags Key=Name,Value="{{CloudFormationStack}} {{Role}}" Key=Stack,Value="{{CloudFormationStack}}"

