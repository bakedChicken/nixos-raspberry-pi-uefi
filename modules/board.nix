# One board family's options and configuration. Runtime: firmware on the ESP, the mainline device tree,
# the partition layout. On demand: system.build.raspberryPiImage, an installable disk image built without a VM.
spec: {
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: let
  inherit (lib) mkOption mkEnableOption mkDefault mkIf types;
  cfg = config.hardware.${spec.name}.uefi;

  uefiFirmware = pkgs.callPackage ../pkgs/rpi-uefi-firmware.nix {board = spec.name;};
  gpuFirmware = "${pkgs.raspberrypifw}/share/raspberrypi/boot";

  # Everything the GPU firmware and UEFI read from the ESP, by path on the ESP
  firmwareFiles =
    {
      "RPI_EFI.fd" = "${uefiFirmware}/RPI_EFI.fd";
      "config.txt" = pkgs.writeText "config.txt" cfg.configTxt;
    }
    // lib.genAttrs (spec.gpuFirmware ++ spec.vendorDeviceTrees) (f: "${gpuFirmware}/${f}")
    // lib.listToAttrs (map (f: lib.nameValuePair "overlays/${f}" "${gpuFirmware}/overlays/${f}") spec.overlays);

  toplevel = config.system.build.toplevel;
  # The image's boot entry, in the layout NixOS's systemd-boot installer manages: the first switch replaces it with
  # the system's generations and removes these files (it garbage-collects nixos-*.conf entries and EFI/nixos)
  imageBootFiles = {
    "/EFI/nixos/image-kernel.efi" = "${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile}";
    "/EFI/nixos/image-initrd.efi" = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
    "/EFI/nixos/image-devicetree.efi" = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
    "/loader/entries/nixos-image.conf" = pkgs.writeText "nixos-image.conf" ''
      title NixOS (installation image)
      sort-key nixos
      linux /EFI/nixos/image-kernel.efi
      initrd /EFI/nixos/image-initrd.efi
      devicetree /EFI/nixos/image-devicetree.efi
      options init=${toplevel}/init ${toString config.boot.kernelParams}
    '';
  };
  efiArch = pkgs.stdenv.hostPlatform.efiArch;
  hostname = config.networking.hostName;
  rootFsType = config.fileSystems."/".fsType;
  # A UUID derived from the hostname, so every machine's image gets its own disk and partition UUIDs
  hash = builtins.hashString "sha256" hostname;
  seed = with lib; "${substring 0 8 hash}-${substring 8 4 hash}-4${substring 13 3 hash}-8${substring 17 3 hash}-${substring 20 12 hash}";
in {
  imports = ["${modulesPath}/image/repart.nix"];

  options.hardware.${spec.name}.uefi = {
    enable = mkEnableOption ''
      booting ${spec.description} through UEFI: firmware built from EDK2 on the ESP, your EFI boot loader and the
      mainline kernel with its own device tree. Also provides `system.build.raspberryPiImage`, an image to write to
      the SD card. The device tree defaults to `${spec.deviceTree}`; set `hardware.deviceTree.name` for another
      board of the family'';

    serialConsole = mkOption {
      type = types.nullOr types.str;
      default = "ttyS1,115200n8";
      description = ''
        Kernel console on the GPIO 14/15 UART. Mainline Linux names the Pi's mini UART ttyS1. null for none.
      '';
    };

    configTxt = mkOption {
      type = types.lines;
      default = spec.configTxt;
      description = ''
        config.txt for the GPU firmware. The default loads the UEFI firmware as the ARM stub, as the Pi Firmware Task
        Force ships it; append lines to change firmware settings.
      '';
    };

    rootDevice = mkOption {
      type = types.str;
      default = "/dev/mmcblk0";
      description = "Disk the system boots from; the root partition grows to fill it on first boot.";
    };
  };

  config = mkIf cfg.enable {
    # Boot chain: GPU firmware -> UEFI (RPI_EFI.fd) -> the configured EFI boot loader -> Linux. The firmware files
    # reach the ESP through that boot loader, so every switch keeps them in place.
    assertions = [
      {
        assertion = config.boot.loader.systemd-boot.enable || (config.boot.loader.grub.enable && config.boot.loader.grub.efiSupport);
        message = "hardware.${spec.name}.uefi installs the firmware through the boot loader: enable boot.loader.systemd-boot, or boot.loader.grub with efiSupport.";
      }
    ];
    boot.loader = {
      systemd-boot.extraFiles = firmwareFiles;
      grub.extraFiles = firmwareFiles;
      # The firmware keeps its variables in RPI_EFI.fd, which every switch reinstalls
      efi.canTouchEfiVariables = mkDefault false;
    };
    hardware.deviceTree = {
      name = mkDefault spec.deviceTree;
      # The mainline device tree starts the secondary CPUs with spin-table, but the UEFI firmware's Trusted Firmware-A
      # holds them for PSCI. The firmware patches the device tree it passes on the same way; the boot loader replaces
      # that one with the mainline device tree, so the patch is applied here too.
      overlays = [
        {
          name = "raspberry-pi-uefi-psci";
          dtsText = ''
            /dts-v1/;
            /plugin/;
            / {
              compatible = "${spec.soc}";
              fragment@0 {
                target-path = "/";
                __overlay__ {
                  psci {
                    compatible = "arm,psci-1.0";
                    method = "smc";
                  };
                };
              };
              ${lib.concatMapStrings (n: ''
              fragment@${toString (n + 1)} {
                target-path = "/cpus/cpu@${toString n}";
                __overlay__ {
                  enable-method = "psci";
                };
              };
            '') (lib.range 0 3)}
            };
          '';
        }
      ];
    };
    boot.kernelParams =
      # The UEFI firmware offers ACPI and a device tree; Linux on the Pi works best with the device tree
      ["acpi=off"]
      ++ lib.optional (cfg.serialConsole != null) "console=${cfg.serialConsole}"
      ++ ["console=tty0"];

    fileSystems = {
      "/" = {
        device = mkDefault "/dev/disk/by-partlabel/root";
        # The image's root filesystem follows this; ext4 unless the system says otherwise
        fsType = mkDefault "ext4";
        # Grow the filesystem with the partition on first boot (x-systemd.growfs)
        autoResize = mkDefault true;
        # Lists merge with NixOS's own mount options
        options = mkIf (rootFsType == "btrfs") [
          "compress=zstd"
          "noatime"
        ];
      };
      "/boot" = {
        device = mkDefault "/dev/disk/by-partlabel/esp";
        fsType = mkDefault "vfat";
        options = ["umask=0077"];
      };
    };

    # First boot of an image: grow the root partition and filesystem to the disk. systemd-repart keeps a hybrid MBR,
    # growpart does not.
    boot.initrd.systemd = {
      enable = mkDefault true;
      repart = {
        enable = mkDefault true;
        device = mkDefault cfg.rootDevice;
      };
      # systemd-repart and mkfs.btrfs copy the store with the write bit set (nixpkgs#361903); store paths have to be
      # read-only. Runs once, while the root is still writable, before Nix registers the paths.
      services.raspberry-pi-uefi-store-permissions = {
        description = "Make the image's Nix store read-only";
        wantedBy = ["initrd.target"];
        after = ["sysroot.mount"];
        requires = ["sysroot.mount"];
        # initrd.target, so the switch to the real root waits for it instead of stopping it
        before = ["initrd.target"];
        unitConfig = {
          DefaultDependencies = false;
          ConditionPathExists = "/sysroot/nix-path-registration";
        };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.findutils}/bin/find /sysroot/nix/store -mindepth 1 -maxdepth 1 ! -type l -exec ${pkgs.coreutils}/bin/chmod -R a-w {} +";
        };
      };
      storePaths = [
        "${pkgs.findutils}/bin/find"
        "${pkgs.coreutils}/bin/chmod"
      ];
    };
    systemd.repart.partitions = {
      "10-esp".Type = "esp";
      "20-root".Type = "root";
    };
    # Register the image's store paths with Nix, as the nixpkgs SD image does
    boot.postBootCommands = ''
      if [ -f /nix-path-registration ]; then
        ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration && rm /nix-path-registration
        ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
      fi
    '';

    # The install image, only evaluated when built: a GPT disk with the ESP (systemd-boot and one boot entry for the first
    # boot, and the firmware) and the root partition with the system closure
    image.repart = {
      enable = true;
      name = hostname;
      inherit seed;
      partitions = {
        esp = {
          contents =
            {
              "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source = "${config.systemd.package}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
            }
            // lib.mapAttrs (_: source: {inherit source;}) imageBootFiles
            // lib.mapAttrs' (path: source: lib.nameValuePair "/${path}" {inherit source;}) firmwareFiles;
          repartConfig = {
            Type = "esp";
            Format = "vfat";
            Label = "esp";
            SizeMinBytes = "512M";
          };
        };
        root = {
          storePaths = [toplevel];
          contents."/nix-path-registration".source = "${pkgs.closureInfo {rootPaths = [toplevel];}}/registration";
          repartConfig = {
            Type = "root";
            Format = rootFsType;
            Label = "root";
            Minimize = "guess";
            GrowFileSystem = true;
          };
        };
      };
    };

    system.build.raspberryPiImage =
      pkgs.runCommand "${hostname}-${spec.name}.img.zst" {
        nativeBuildInputs = with pkgs; [
          gptfdisk
          util-linux
          zstd
        ];
      } ''
        cp ${config.image.repart.image}/${config.image.fileName} image.raw
        chmod u+w image.raw
        ${lib.optionalString spec.hybridMbr ''
          # Mirror the ESP into the MBR as FAT32 (LBA) so the boot ROM finds the firmware
          sgdisk --hybrid 1:EE image.raw
          sfdisk --label-nested dos --part-type image.raw 1 0x0c
        ''}
        zstd -T0 image.raw -o $out
      '';
  };
}
