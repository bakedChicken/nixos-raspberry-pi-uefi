# RPI_EFI.fd, the UEFI firmware the Raspberry Pi's GPU firmware loads as its ARM stub, built from EDK2 the way
# the Pi Firmware Task Force builds its releases.
{
  lib,
  stdenv,
  buildPackages,
  fetchFromGitHub,
  python3,
  acpica-tools,
  board,
}: let
  sources = import ./edk2-sources.nix {inherit fetchFromGitHub;};
  platform =
    {
      pi3 = "RPi3";
      pi4 = "RPi4";
    }
    .${
      board
    };
  buildFlags =
    [
      "-D SECURE_BOOT_ENABLE=TRUE"
      "-D INCLUDE_TFTP_COMMAND=TRUE"
      "-D NETWORK_ISCSI_ENABLE=TRUE"
    ]
    ++ lib.optional (board == "pi4") "-D SMC_PCI_SUPPORT=1";
in
  stdenv.mkDerivation {
    pname = "${lib.toLower platform}-uefi-firmware";
    inherit (sources) version;

    srcs = [
      sources.edk2
      sources.edk2-platforms
      sources.edk2-non-osi
    ];
    unpackPhase = ''
      runHook preUnpack
      cp -r ${sources.edk2} edk2
      cp -r ${sources.edk2-platforms} edk2-platforms
      cp -r ${sources.edk2-non-osi} edk2-non-osi
      chmod -R u+w .
      patchShebangs edk2/BaseTools
      runHook postUnpack
    '';

    # BaseTools run on the build machine; the firmware is compiled with the (cross) compiler for aarch64
    depsBuildBuild = [
      buildPackages.stdenv.cc
      buildPackages.libuuid
    ];
    nativeBuildInputs = [
      python3
      acpica-tools
    ];
    # EDK2 brings its own compiler and linker flags
    hardeningDisable = ["all"];
    env = {
      GCC_AARCH64_PREFIX = stdenv.cc.targetPrefix;
      PYTHON_COMMAND = "python3";
    };

    buildPhase = ''
      runHook preBuild
      export WORKSPACE=$PWD
      export PACKAGES_PATH=$WORKSPACE/edk2:$WORKSPACE/edk2-platforms:$WORKSPACE/edk2-non-osi
      make -C edk2/BaseTools/Source/C -j $NIX_BUILD_CORES CC=$CC_FOR_BUILD CXX=$CXX_FOR_BUILD
      # edksetup.sh parses "$@" as its own options
      set --
      source edk2/edksetup.sh
      build -a AARCH64 -t GCC -b RELEASE -n $NIX_BUILD_CORES \
        -p Platform/RaspberryPi/${platform}/${platform}.dsc \
        --pcd gEfiMdeModulePkgTokenSpaceGuid.PcdFirmwareVendor=L"https://github.com/bakedChicken/nixos-raspberry-pi-uefi" \
        --pcd gEfiMdeModulePkgTokenSpaceGuid.PcdFirmwareVersionString=L"UEFI Firmware v${sources.version}" \
        ${lib.concatStringsSep " " buildFlags}
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm644 $WORKSPACE/Build/${platform}/RELEASE_GCC/FV/RPI_EFI.fd $out/RPI_EFI.fd
      runHook postInstall
    '';

    meta = {
      description = "UEFI firmware for the Raspberry Pi ${lib.removePrefix "RPi" platform}, built from EDK2";
      homepage = "https://github.com/pftf/${platform}";
      # EDK2 and edk2-platforms; edk2-non-osi adds a logo and, for the Pi 3, prebuilt Trusted Firmware-A
      license = with lib.licenses; [
        bsd2Patent
        bsd3
      ];
      sourceProvenance = with lib.sourceTypes; [
        fromSource
        binaryFirmware
      ];
      platforms = ["aarch64-linux"];
    };
  }
