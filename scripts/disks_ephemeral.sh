#!/bin/bash -e


# create sastmp directory/mountpoint
if [ ! -d /sastmp/ ]; then
    mkdir /sastmp
fi

# find the nvm drive devices
drives=""
drive_count=0
nvm_drives=$(lsblk  -d -n --output NAME | grep nvm || :)
for device_name in $nvm_drives; do

  device_path="/dev/$device_name"

  if [ -b "$device_path" ]; then
    echo "Detected ephemeral disk: $device_path"
    drives="$drives $device_path"
    drive_count=$((drive_count + 1 ))
  else
    echo "Ephemeral disk $device_path is not present. skipping"
  fi

done

if [ "$drive_count" = 0 ]; then

  echo "No ephemeral disks detected."



else

  # format (raid) ephemeral drives if needed
  if  [ "$(blkid /dev/md0 | grep xfs)" = "" ]; then

    # find the drive devices
    drives=""
    drive_count=0
    nvm_drives=$(lsblk  -d -n --output NAME | grep nvm)
    for device_name in $nvm_drives; do

      device_path="/dev/$device_name"

      if [ -b "$device_path" ]; then
        echo "Detected ephemeral disk: $device_path"
        drives="$drives $device_path"
        drive_count=$((drive_count + 1 ))
      else
        echo "Ephemeral disk $device_path is not present. skipping"
      fi

    done

     # overwrite first few blocks in case there is a filesystem, otherwise mdadm will prompt for input
    for drive in $drives; do
      dd if=/dev/zero of="$drive" bs=4096 count=1024
    done

    # create RAID and filesystem
    READAHEAD=16384
    partprobe
    mdadm --create --verbose /dev/md0 --level=0 -c256 --force --raid-devices=$drive_count $drives
    echo DEVICE "$drives" | tee /etc/mdadm.conf
    mdadm --detail --scan | tee -a /etc/mdadm.conf
    blockdev --setra $READAHEAD /dev/md0

    mkfs -t xfs /dev/md0

  fi

  # in case it was mounted already...
  umount /sastmp || true
  # for some instances, /mnt is the default instance store, already mounted. so we unmount it:
  umount /mnt || true

  mount -t xfs -o noatime /dev/md0 /sastmp

fi

if [ ! -d /sastmp/cascache/ ]; then
    mkdir /sastmp/cascache
fi
chmod 777 /sastmp/cascache

