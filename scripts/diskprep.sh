#!/bin/bash -e
set -x


METADATA_URL_BASE="http://169.254.169.254/latest"

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
    [ "$(blkid $device_path | grep ext4)" = "" ] && mkfs.ext4 $device_path
    # add to fstab if needed and mount
    FSTAB="$device_path      $dir   ext4    defaults,nofail        0       2"
    ! (grep "$FSTAB" /etc/fstab) &&  echo "$FSTAB" | tee -a /etc/fstab
    umount $dir || true
    mount $dir
  fi

  # TODO: optional additional EBS library/caslib

done


ephemeral_count=0
ephemerals=$(curl --silent $METADATA_URL_BASE/meta-data/block-device-mapping/ | grep ephemeral || true)
for e in $ephemerals; do
  ephemeral_count=$((ephemeral_count+1))
  device_name=$(curl --silent $METADATA_URL_BASE/meta-data/block-device-mapping/$e)
  device_path="/dev/nvme0n$ephemeral_count"

  # mount nvme0n1 to /sastmp
  if [[ "$device_name" == "sdb" ]]  && [ -b "$device_path" ] ; then
    dir="/sastmp"
    mkdir -p $dir
    # format if needed
    [ "$(blkid $device_path | grep ext4)" = "" ] && mkfs.ext4 -E nodiscard $device_path
    # add to fstab if needed and mount
    FSTAB="$device_path $dir ext4 defaults,nofail,discard 0 2"
    ! (grep "$FSTAB" /etc/fstab) &&  echo "$FSTAB" | tee -a /etc/fstab
    umount $dir || true
    mount $dir

    # TODO move this into pre.deployment.yml
    chmod 777 ${dir}
    mkdir -p ${dir}/cascache
    mkdir -p ${dir}/saswork
 #   chown cas ${dir}/cascache
    chmod 777 ${dir}/cascache
#    chown sas ${dir}/saswork
    chmod 777 ${dir}/saswork
  fi

  # TODO: additional ephemeral drives for multi-path saswork/cascache

done

