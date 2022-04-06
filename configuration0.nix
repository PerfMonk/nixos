# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "zfs" ];
  boot.loader.supportsInitrdSecrets = true;

# Use the GRUB 2 boot loader.
#  boot.loader.grub = {
#    enable = true;
#    version =2;
#    device = "nodev";
#    efiSupport = true;
#    enableCryptodisk = true;
#    zfsSupport = true;
#  };
  boot.zfs.requestEncryptionCredentials = true;
  boot.zfs.enableUnstable = true;
  services.zfs.autoSnapshot.enable = true;
  services.zfs.autoScrub.enable = true;
  services.zfs.autoScrub.pools = ["rpool"];
#  boot.loader.grub.copyKernels = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efi"; 
###  https://gist.github.com/walkermalling/23cf138432aee9d36cf59ff5b63a2a58
  boot.initrd.luks.devices = {
   root = {
     device = "/dev/disk/by-uuid/1dd3bc65-70dd-48aa-ad62-fe56b63a1c04"; ## Use blkid to find this UUID
     preLVM = true;
#     keyFile = "/keyfile.bin";
   };
  };

   boot.initrd.luks.devices."cryptroot".keyFile = "/keyfile.bin";
#   boot.initrd.secrets = {
#      "/keyfile.bin" = "/keyfile.bin";
#   };

  networking.hostName = "clinix"; # Define your hostname.
  networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.hostId = "4441267e";

  # Set your time zone.
  time.timeZone = "America/Toronto";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  networking.interfaces.wlp1s0.useDHCP = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
   i18n.defaultLocale = "fr_CA.UTF-8";
   console = {
     font = "Lat2-Terminus16";
     keyMap = "ca";
   };

  # Enable the X11 windowing system.
  services.xserver.enable = true;


  # Enable the Plasma 5 Desktop Environment.
  services.xserver.displayManager.sddm.enable = true;
  services.xserver.desktopManager.plasma5.enable = true;
  

  # Configure keymap in X11
   services.xserver.layout = "ca";
  # services.xserver.xkbOptions = "eurosign:e";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
   users.users.bt = {
     isNormalUser = true;
     extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
   };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
   environment.systemPackages = with pkgs; [
     vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
     wget
     firefox
   ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
   programs.mtr.enable = true;
   programs.gnupg.agent = {
     enable = true;
     enableSSHSupport = true;
   };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
   services.openssh.enable = true;

 systemd.services.partprobe = {
   enable = true;
   description = "partprobe after cryptsetup";
   unitConfig = {
     Type = "oneshot";
     After = "cryptsetup.target";
     DefaultDepedencies = "no";
   };
   before = [ "cryptroot1.mount" ];
   serviceConfig = {
     Type = "oneshot";
     ExecStart = "/sbin/partprobe /dev/mapper/cryptroot";
   };
 };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "21.11"; # Did you read the comment?

}
