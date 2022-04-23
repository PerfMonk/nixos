{ config, pkgs, ... }:

{ boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "e9534b62";
  boot.zfs.devNodes = "/dev/disk/by-id";
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
  swapDevices = [
    { device = "/dev/disk/by-id/usb-SPCC_Sol_id_State_Disk_1-0:0-part4"; randomEncryption.enable = true; }
  ];
  systemd.services.zfs-mount.enable = false;
  environment.etc."machine-id".source = "/state/etc/machine-id";
  environment.etc."zfs/zpool.cache".source
    = "/state/etc/zfs/zpool.cache";
  boot.loader.efi.efiSysMountPoint = "/boot/efis/usb-SPCC_Sol_id_State_Disk_1-0:0-part1";
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
       cp -r /boot/efis/usb-SPCC_Sol_id_State_Disk_1-0:0-part1/EFI $ESP_MIRROR
       for i in /boot/efis/*; do
        cp -r $ESP_MIRROR/EFI $i
       done
       rm -rf $ESP_MIRROR
    '';
    grub.devices = [
      "/dev/disk/by-id/usb-SPCC_Sol_id_State_Disk_1-0:0"
    ];
  };
  environment.systemPackages = [ pkgs.cryptsetup ];
  boot.initrd.luks.devices = {
    "usb-SPCC_Sol_id_State_Disk_1-0:0-part2-luks-bpool_scx4fr" = {
      device = "/dev/disk/by-id/usb-SPCC_Sol_id_State_Disk_1-0:0-part2";
      allowDiscards = true;
      keyFile = "/etc/cryptkey.d/bpool_scx4fr-key-luks";
    };
  };
  boot.initrd.secrets = {
    "/etc/cryptkey.d/rpool_scx4fr-nixos-key-zfs" = "/etc/cryptkey.d/rpool_scx4fr-nixos-key-zfs";
    "/etc/cryptkey.d/bpool_scx4fr-key-luks" = "/etc/cryptkey.d/bpool_scx4fr-key-luks";
  };
  boot.loader.grub.enableCryptodisk = true;
}
