{
  description = "Boot NixOS on the Raspberry Pi 3 and 4 like a PC: UEFI firmware built from EDK2, an EFI boot loader, the mainline kernel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    treefmt-nix,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        treefmt-nix.flakeModule
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      flake = {
        nixosModules.default = ./modules;

        overlays.default = final: _prev: {
          rpi3-uefi-firmware = final.callPackage ./pkgs/rpi-uefi-firmware.nix {board = "pi3";};
          rpi4-uefi-firmware = final.callPackage ./pkgs/rpi-uefi-firmware.nix {board = "pi4";};
        };
      };

      perSystem = {
        pkgs,
        system,
        ...
      }: let
        # The firmware runs on aarch64: built natively there, cross-compiled elsewhere
        aarch64Pkgs =
          if system == "aarch64-linux"
          then pkgs
          else pkgs.pkgsCross.aarch64-multiplatform;

        # Minimal systems that opt in, evaluated by `nix flake check`
        example = board:
          nixpkgs.lib.nixosSystem {
            modules = [
              self.nixosModules.default
              {
                nixpkgs.hostPlatform = "aarch64-linux";
                nixpkgs.config.allowUnfree = true;
                networking.hostName = "example-${board}";
                hardware.${board}.uefi.enable = true;
                boot.loader.systemd-boot.enable = true;
                system.stateVersion = "26.05";
              }
            ];
          };
        evaluates = board: let
          config = (example board).config;
        in
          pkgs.writeText "example-${board}-evaluates" ''
            ${builtins.unsafeDiscardStringContext config.system.build.toplevel.drvPath}
            ${builtins.unsafeDiscardStringContext config.system.build.raspberryPiImage.drvPath}
          '';
      in {
        packages = {
          rpi3-uefi-firmware = aarch64Pkgs.callPackage ./pkgs/rpi-uefi-firmware.nix {board = "pi3";};
          rpi4-uefi-firmware = aarch64Pkgs.callPackage ./pkgs/rpi-uefi-firmware.nix {board = "pi4";};
        };

        checks = {
          example-pi3 = evaluates "pi3";
          example-pi4 = evaluates "pi4";
        };

        treefmt = {
          projectRootFile = "flake.nix";
          programs.alejandra.enable = true;
          programs.prettier.enable = true;
        };

        devShells.default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            nixd
            zstd
            gptfdisk
          ];
        };
      };
    };
}
