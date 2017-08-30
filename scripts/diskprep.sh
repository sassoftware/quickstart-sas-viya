#!/bin/bash -e


yum -y -d0 install mdadm

# pin the metadata version to avoid surprise updates
METADATA_URL_BASE="http://169.254.169.254/2012-01-12"


# determine the device naming scheme (xvd vs sd)
root_drive=$(df -h | grep -v grep | awk 'NR==2{print $1}')
if [ "${root_drive:0:8}" == "/dev/xvd" ]; then
  echo "Detected 'xvd' drive naming scheme (root: $root_drive)"
  DRIVE_SCHEME='xvd'
else
  echo "Detected 'sd' drive naming scheme (root: $root_drive)"
  DRIVE_SCHEME='sd'
fi



ebs_count=0
ebss=$(curl --silent $METADATA_URL_BASE/meta-data/block-device-mapping/ | grep ebs || true)
for e in $ebss; do
  device_name=$(curl --silent $METADATA_URL_BASE/meta-data/block-device-mapping/$e)
  # might have to convert 'sdb' -> 'xvdb'
  device_name=$(echo $device_name | sed "s/sd/$DRIVE_SCHEME/")
  device_path="/dev/$device_name"

  # mount the xxxg device to /opt/sas
  if [[ "$device_path" == "/dev/${DRIVE_SCHEME}g" ]]  && [ -b "$device_path" ] ; then
    dir="/opt/sas"
    mkdir -p $dir
    # format if needed
    [ "$(blkid $device_path | grep xfs)" = "" ] && mkfs.xfs $device_path
    # add to fstab if needed and mount
    FSTAB="$device_path      $dir   xfs    defaults,nofail        0       2"
    ! (grep "$FSTAB" /etc/fstab) &&  echo "$FSTAB" | tee -a /etc/fstab
    umount $dir || true
    mount $dir
  fi

  # TODO: optional additional EBS library/caslib

done


# format (raid) ephemeral drives if needed
if  [ "$(blkid /dev/md0 | grep xfs)" = "" ]; then

  drives=""
  drive_count=0
  nvm_drives=$(lsblk  -d -n --output NAME | grep nvm)


  for device_name in $nvm_drives; do

    device_path="/dev/$device_name"

    if [ -b $device_path ]; then
      echo "Detected ephemeral disk: $device_path"
      drives="$drives $device_path"
      drive_count=$((drive_count + 1 ))
    else
      echo "Ephemeral disk $device_path is not present. skipping"
    fi

  done

  if [ "$drive_count" = 0 ]; then
    echo "No ephemeral disk detected. exiting"
    exit 0
  fi

  # in case it was mounted already...
  umount /sastmp || true
  # for some instances, /mnt is the default instance store, already mounted. so we unmount it:
  umount /mnt || true


  # create RAID and filesystem if needed

  if [ "$(blkid /dev/md0 | grep xfs)" = "" ]; then

    # overwrite first few blocks in case there is a filesystem, otherwise mdadm will prompt for input
    for drive in $drives; do
      dd if=/dev/zero of=$drive bs=4096 count=1024
    done

    READAHEAD=16384
    partprobe
    mdadm --create --verbose /dev/md0 --level=0 -c256 --force --raid-devices=$drive_count $drives
    echo DEVICE $drives | tee /etc/mdadm.conf
    mdadm --detail --scan | tee -a /etc/mdadm.conf
    blockdev --setra $READAHEAD /dev/md0

    mkfs -t xfs /dev/md0
  fi

  if [ ! -d /sastmp/ ]; then
      mkdir /sastmp
  fi

  mount -t xfs -o noatime /dev/md0 /sastmp

  if [ ! -d /sastmp/saswork/ ]; then
      mkdir /sastmp/saswork
  fi
  chmod 777 /sastmp/saswork
  if [ ! -d /sastmp/cascache/ ]; then
      mkdir /sastmp/cascache
  fi
  chmod 777 /sastmp/cascache

fi