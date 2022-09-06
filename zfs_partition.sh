#!/usr/bin/env bash

# My NixOS install with encrypted root and swap
# on disk usb-SPCC_Sol_id_State_Disk_1-0:0  (512MB)
# ├─sda1            ESP  /boot/efi   (2GB)
# ├─sda2            BOOT pool /boot ZFS (4GB))
# ├─sda3            ROOT pool /     ZFS encrypted (489)
# └─sda4            SWAP LUKS CONTAINER  (17GB)
#   └─cryptswap     LUKS MAPPER
#     └─cryptswap   SWAP
# └─sda5            legacy boot  (1MB)
#
### REF: https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/Root%20on%20ZFS.html
#
set -e

pprint () {
    local cyan="\e[96m"
    local default="\e[39m"
    # ISO8601 timestamp + ms
    local timestamp
    timestamp=$(date +%FT%T.%3NZ)
    echo -e "${cyan}${timestamp} $1${default}" 1>&2
}
# Unique pool suffix
INST_UUID=$(dd if=/dev/urandom bs=1 count=100 2>/dev/null | tr -dc 'a-z0-9' | cut -c-6)

# Installation ZFS PATH
INST_ID=nixos

# Root on ZFS configuration filename
INST_CONFIG_FILE='zfs.nix'

# Set DISK
select ENTRY in $(ls /dev/disk/by-id/);
do
    DISK="/dev/disk/by-id/$ENTRY"
    echo "Installing system on $ENTRY."
    break
done
###Set primary disk and vdev topology (anyway we have only one disk)
INST_PRIMARY_DISK=$(echo $DISK | cut -f1 -d\ )
INST_VDEV=

read -p "> Is this an SSD and wipe it : $ENTRY Y/N ? " -n 1 -r
echo # move to a new line
if [[ "$REPLY" =~ ^[Yy]$ ]]
then
    for i in ${DISK}; do    # wipe SSD
      blkdiscard -f $i &
    done
    wait
    # Clear disk
    #wipefs -af "$DISK"
    #sgdisk -Zo "$DISK"
fi

# Set ESP size
INST_PARTSIZE_ESP=2 # in GB

# Set Boot pool size (recommandation min 4Gb)
INST_PARTSIZE_BPOOL=4

# Set swap size (I use hibernation, ajust to your need)
INST_PARTSIZE_SWAP=17

# Set root pool size (rest of the disk if not set)
INST_PARTSIZE_RPOOL=

# Partition the disk
pprint "Partitioning the disk"
for i in ${DISK}; do
sgdisk --zap-all $i
sgdisk -n1:1M:+${INST_PARTSIZE_ESP}G -t1:EF00 $i
sgdisk -n2:0:+${INST_PARTSIZE_BPOOL}G -t2:BE00 $i
if [ "${INST_PARTSIZE_SWAP}" != "" ]; then
    sgdisk -n4:0:+${INST_PARTSIZE_SWAP}G -t4:8200 $i
fi
if [ "${INST_PARTSIZE_RPOOL}" = "" ]; then
    sgdisk -n3:0:0   -t3:BF00 $i
else
    sgdisk -n3:0:+${INST_PARTSIZE_RPOOL}G -t3:BF00 $i
fi
sgdisk -a1 -n5:24K:+1000K -t5:EF02 $i
done

# Inform kernel
partprobe "$DISK"
sleep 1


## You should not need to modify any options of the boot pool

pprint "Create boot pool"
disk_num=0; for i in $DISK; do disk_num=$(( $disk_num + 1 )); done
if [ $disk_num -gt 1 ]; then INST_VDEV_BPOOL=mirror; fi


zpool create \
    -o compatibility=grub2 \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl \
    -O canmount=off \
    -O compression=lz4 \
    -O devices=off \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=/boot \
    -R /mnt \
    bpool_$INST_UUID \
     $INST_VDEV_BPOOL \
    $(for i in ${DISK}; do
       printf "$i-part2 ";
      done)

pprint "Create root pool"
zpool create \
    -o ashift=12 \
    -o autotrim=on \
    -R /mnt \
    -O acltype=posixacl \
    -O canmount=off \
    -O compression=zstd \
    -O dnodesize=auto \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=/ \
    rpool_$INST_UUID \
    $INST_VDEV \
   $(for i in ${DISK}; do
      printf "$i-part3 ";
     done)

pprint "Create encrypted root system container, use strong password"
zfs create \
 -o canmount=off \
 -o mountpoint=none \
 -o encryption=aes-256-gcm \
 -o keylocation=prompt \
 -o keyformat=passphrase \
 rpool_$INST_UUID/$INST_ID

pprint "Create other system datasets"
zfs create -o canmount=off -o mountpoint=none bpool_$INST_UUID/$INST_ID
zfs create -o canmount=off -o mountpoint=none bpool_$INST_UUID/$INST_ID/BOOT
zfs create -o canmount=off -o mountpoint=none rpool_$INST_UUID/$INST_ID/ROOT
zfs create -o canmount=off -o mountpoint=none rpool_$INST_UUID/$INST_ID/DATA
zfs create -o mountpoint=/boot -o canmount=noauto bpool_$INST_UUID/$INST_ID/BOOT/default
zfs create -o mountpoint=/ -o canmount=off    rpool_$INST_UUID/$INST_ID/DATA/default
zfs create -o mountpoint=/ -o canmount=off    rpool_$INST_UUID/$INST_ID/DATA/local
zfs create -o mountpoint=/ -o canmount=noauto rpool_$INST_UUID/$INST_ID/ROOT/default
zfs mount rpool_$INST_UUID/$INST_ID/ROOT/default
zfs mount bpool_$INST_UUID/$INST_ID/BOOT/default
for i in {usr,var,var/lib};
do
    zfs create -o canmount=off rpool_$INST_UUID/$INST_ID/DATA/default/$i
done
for i in {home,root,srv,usr/local,var/log,var/spool};
do
    zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/$i
done
chmod 750 /mnt/root
for i in {nix,}; do
    zfs create -o canmount=on -o mountpoint=/$i rpool_$INST_UUID/$INST_ID/DATA/local/$i
done

zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/state
for i in {/etc/nixos,/etc/cryptkey.d}; do
  mkdir -p /mnt/state/$i /mnt/$i
  mount -o bind /mnt/state/$i /mnt/$i
done
zfs create -o mountpoint=/ -o canmount=noauto rpool_$INST_UUID/$INST_ID/ROOT/empty
zfs snapshot rpool_$INST_UUID/$INST_ID/ROOT/empty@start

pprint "Format and mount ESP"
for i in ${DISK}; do
 mkfs.vfat -n EFI ${i}-part1
 mkdir -p /mnt/boot/efis/${i##*/}-part1
 mount -t vfat ${i}-part1 /mnt/boot/efis/${i##*/}-part1
done

pprint "Create optional user datasets to omit data from rollback"
zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/games
zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/www
# for GNOME
zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/lib/AccountsService
# for Docker
zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/lib/docker
# for NFS
zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/lib/nfs
# for LXC
zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/lib/lxc
# for LibVirt
zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/lib/libvirt
##other application
# zfs create -o canmount=on rpool_$INST_UUID/$INST_ID/DATA/default/var/lib/$name

pprint "Generate NixOS configuration"
nixos-generate-config --root /mnt

pprint "Edit config file to import ZFS options"
sed -i "s|./hardware-configuration.nix|./hardware-configuration-zfs.nix ./${INST_CONFIG_FILE}|g" /mnt/etc/nixos/configuration.nix
# backup, prevent being overwritten by nixos-generate-config
mv /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hardware-configuration-zfs.nix

# ZFS Options
tee -a /mnt/etc/nixos/${INST_CONFIG_FILE} <<EOF
{ config, pkgs, ... }:

{ boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "$(head -c 8 /etc/machine-id)";
  boot.zfs.devNodes = "${INST_PRIMARY_DISK%/*}";
EOF

# ZFS datasets to be mounted with zfsutils option
sed -i 's|fsType = "zfs";|fsType = "zfs"; options = [ "zfsutil" "X-mount.mkdir" ];|g' \
/mnt/etc/nixos/hardware-configuration-zfs.nix

# Allow EFI partition mounting to fail at boot
sed -i 's|fsType = "vfat";|fsType = "vfat"; options = [ "x-systemd.idle-timeout=1min" "x-systemd.automount" "noauto" ];|g' \
/mnt/etc/nixos/hardware-configuration-zfs.nix

# Restric to kernels version that support ZFS
tee -a /mnt/etc/nixos/${INST_CONFIG_FILE} <<EOF
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
EOF

# Disable cache
mkdir -p /mnt/state/etc/zfs/
rm -f /mnt/state/etc/zfs/zpool.cache
touch /mnt/state/etc/zfs/zpool.cache
chmod a-w /mnt/state/etc/zfs/zpool.cache
chattr +i /mnt/state/etc/zfs/zpool.cache

# If swap is enable
if [ "${INST_PARTSIZE_SWAP}" != "" ]; then
sed -i '/swapDevices/d' /mnt/etc/nixos/hardware-configuration-zfs.nix

tee -a /mnt/etc/nixos/${INST_CONFIG_FILE} <<EOF
  swapDevices = [
EOF
for i in $DISK; do
tee -a /mnt/etc/nixos/${INST_CONFIG_FILE} <<EOF
    { device = "$i-part4"; randomEncryption.enable = true; }
EOF
done
tee -a /mnt/etc/nixos/${INST_CONFIG_FILE} <<EOF
  ];
EOF
fi

# For immutable root file system, save machine-id and other files
mkdir -p /mnt/state/etc/{ssh,zfs}
systemd-machine-id-setup --print > /mnt/state/etc/machine-id
tee -a /mnt/etc/nixos/${INST_CONFIG_FILE} <<EOF
  systemd.services.zfs-mount.enable = false;
  environment.etc."machine-id".source = "/state/etc/machine-id";
  environment.etc."zfs/zpool.cache".source
    = "/state/etc/zfs/zpool.cache";
  boot.loader.efi.efiSysMountPoint = "/boot/efis/${INST_PRIMARY_DISK##*/}-part1";
EOF

# Configure GRUB boot loader for both legacy boot and UEFI
sed -i '/boot.loader/d' /mnt/etc/nixos/configuration.nix
tee -a /mnt/etc/nixos/${INST_CONFIG_FILE} <<-'EOF'
  boot.loader.efi.canTouchEfiVariables = false;
  ##if UEFI firmware can detect entries
  #boot.loader.efi.canTouchEfiVariables = true;

  boot.loader = {
    generationsDir.copyKernels = true;
    ##for problematic UEFI firmware
    grub.efiInstallAsRemovable = true;
    grub.enable = true;
    grub.version = 2;
    grub.copyKernels = true;
    grub.efiSupport = true;
    grub.zfsSupport = true;
    # for systemd-autofs
    grub.extraPrepareConfig = ''
      mkdir -p /boot/efis
      for i in  /boot/efis/*; do mount $i ; done
    '';
    grub.extraInstallCommands = ''
       export ESP_MIRROR=$(mktemp -d -p /tmp)
EOF
tee -a /mnt/etc/nixos/${INST_CONFIG_FILE} <<EOF
       cp -r /boot/efis/${INST_PRIMARY_DISK##*/}-part1/EFI \$ESP_MIRROR
EOF
tee -a /mnt/etc/nixos/${INST_CONFIG_FILE} <<-'EOF'
       for i in /boot/efis/*; do
        cp -r $ESP_MIRROR/EFI $i
       done
       rm -rf $ESP_MIRROR
    '';
    grub.devices = [
EOF
for i in $DISK; do
  printf "      \"$i\"\n" >>/mnt/etc/nixos/${INST_CONFIG_FILE}
done
tee -a /mnt/etc/nixos/${INST_CONFIG_FILE} <<EOF
    ];
  };
EOF

pprint "encrypt boot pool"
# Add package
tee -a /mnt/etc/nixos/${INST_CONFIG_FILE} <<EOF
  environment.systemPackages = [ pkgs.cryptsetup ];
EOF

# LUKS password

while [ 1 -gt 0 ]
do
    read -p "> Enter passphrase ? " -r
    echo # move to a new line
    LUKS_PWD="$REPLY"

    read -p "> Passphrase will be \"$LUKS_PWD\" (y/n) ? " -n 1 -r
    echo # move to a new line
    if [[ "$REPLY" =~ ^[Yy]$ ]]
    then
         break
    fi
done
# Create encryption keys
mkdir -p /mnt/etc/cryptkey.d/
chmod 700 /mnt/etc/cryptkey.d/
dd bs=32 count=1 if=/dev/urandom of=/mnt/etc/cryptkey.d/rpool_$INST_UUID-${INST_ID}-key-zfs
dd bs=32 count=1 if=/dev/urandom of=/mnt/etc/cryptkey.d/bpool_$INST_UUID-key-luks
chmod u=r,go= /mnt/etc/cryptkey.d/*

# Backup boot pool
zfs snapshot -r bpool_$INST_UUID/$INST_ID@pre-luks
zfs send -Rv bpool_$INST_UUID/$INST_ID@pre-luks > /mnt/root/bpool_$INST_UUID-${INST_ID}-pre-luks

# Unmount uefi
for i in ${DISK}; do
 umount /mnt/boot/efis/${i##*/}-part1
done

# Destroy boot pool
zpool destroy bpool_$INST_UUID

# Create luks containers
for i in ${DISK}; do
 cryptsetup luksFormat -q --type luks1 --key-file /mnt/etc/cryptkey.d/bpool_$INST_UUID-key-luks $i-part2
 echo $LUKS_PWD | cryptsetup luksAddKey --key-file /mnt/etc/cryptkey.d/bpool_$INST_UUID-key-luks $i-part2
 cryptsetup open ${i}-part2 ${i##*/}-part2-luks-bpool_$INST_UUID --key-file /mnt/etc/cryptkey.d/bpool_$INST_UUID-key-luks
tee -a /mnt/etc/nixos/${INST_CONFIG_FILE} <<EOF
  boot.initrd.luks.devices = {
    "${i##*/}-part2-luks-bpool_$INST_UUID" = {
      device = "${i}-part2";
      allowDiscards = true;
      keyFile = "/etc/cryptkey.d/bpool_$INST_UUID-key-luks";
    };
  };
EOF
done

# Embed keyFile in initrd
tee -a /mnt/etc/nixos/${INST_CONFIG_FILE} <<EOF
  boot.initrd.secrets = {
    "/etc/cryptkey.d/rpool_$INST_UUID-${INST_ID}-key-zfs" = "/etc/cryptkey.d/rpool_$INST_UUID-${INST_ID}-key-zfs";
    "/etc/cryptkey.d/bpool_$INST_UUID-key-luks" = "/etc/cryptkey.d/bpool_$INST_UUID-key-luks";
  };
EOF

# Recreate boot pool with mappers as vdev
disk_num=0; for i in $DISK; do disk_num=$(( $disk_num + 1 )); done
if [ $disk_num -gt 1 ]; then INST_VDEV_BPOOL=mirror; fi

zpool create \
    -d -o feature@async_destroy=enabled \
    -o feature@bookmarks=enabled \
    -o feature@embedded_data=enabled \
    -o feature@empty_bpobj=enabled \
    -o feature@enabled_txg=enabled \
    -o feature@extensible_dataset=enabled \
    -o feature@filesystem_limits=enabled \
    -o feature@hole_birth=enabled \
    -o feature@large_blocks=enabled \
    -o feature@lz4_compress=enabled \
    -o feature@spacemap_histogram=enabled \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl \
    -O canmount=off \
    -O compression=lz4 \
    -O devices=off \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=/boot \
    -R /mnt \
    bpool_$INST_UUID \
     $INST_VDEV_BPOOL \
    $(for i in ${DISK}; do
       printf "/dev/mapper/${i##*/}-part2-luks-bpool_$INST_UUID ";
      done)

# Restore boot pool backup
zfs recv bpool_${INST_UUID}/${INST_ID} < /mnt/root/bpool_$INST_UUID-${INST_ID}-pre-luks
rm /mnt/root/bpool_$INST_UUID-${INST_ID}-pre-luks

# Mount boot pool and EFI partition
zfs mount bpool_$INST_UUID/$INST_ID/BOOT/default

for i in ${DISK}; do
 mount ${i}-part1 /mnt/boot/efis/${i##*/}-part1
done

# As keys are stored in initrd, set secure permissions for /boot
chmod 700 /mnt/boot

# Change root pool password to key file
mkdir -p /etc/cryptkey.d/
cp /mnt/etc/cryptkey.d/rpool_$INST_UUID-${INST_ID}-key-zfs /etc/cryptkey.d/rpool_$INST_UUID-${INST_ID}-key-zfs
zfs change-key -l \
-o keylocation=file:///etc/cryptkey.d/rpool_$INST_UUID-${INST_ID}-key-zfs \
-o keyformat=raw \
rpool_$INST_UUID/$INST_ID

# Enable GRUB cryptodisk
tee -a /mnt/etc/nixos/${INST_CONFIG_FILE} <<EOF
  boot.loader.grub.enableCryptodisk = true;
EOF

pprint "Important: Back up root dataset key /etc/cryptkey.d/rpool_$INST_UUID-${INST_ID}-key-zfs to a secure location"
pprint "In the possible event of LUKS container corruption, data on root set will only be available with this key"


pprint "Continue at https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/Root%20on%20ZFS/4-system-installation.html"

exit
