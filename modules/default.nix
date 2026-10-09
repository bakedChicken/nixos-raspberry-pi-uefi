# hardware.pi3.uefi and hardware.pi4.uefi, one per SoC family: every board of a family shares the firmware and boot
# chain and differs only in its mainline device tree (hardware.deviceTree.name)
let
  mkBoard = import ./board.nix;
in {
  imports = [
    (mkBoard {
      name = "pi3";
      # The BCM2837 family; not only the Pi 3
      description = "BCM2837 boards: Raspberry Pi 3B, 3B+, 3A+, Compute Module 3 and Zero 2 W";
      # Mainline device tree for the 3B; other boards set hardware.deviceTree.name
      deviceTree = "broadcom/bcm2837-rpi-3-b.dtb";
      # Matches every board of the family; device tree overlays apply by it
      soc = "brcm,bcm2837";
      # Loaded by the GPU firmware before UEFI
      gpuFirmware = [
        "bootcode.bin"
        "start.elf"
        "fixup.dat"
      ];
      vendorDeviceTrees = [
        "bcm2710-rpi-3-b.dtb"
        "bcm2710-rpi-3-b-plus.dtb"
        "bcm2710-rpi-cm3.dtb"
        "bcm2710-rpi-zero-2-w.dtb"
      ];
      overlays = [];
      # From github.com/pftf/RPi3
      configTxt = ''
        arm_64bit=1
        disable_commandline_tags=2
        disable_overscan=1
        enable_uart=1
        uart_2ndstage=1
        armstub=RPI_EFI.fd
        device_tree_address=0x1f0000
        device_tree_end=0x200000
      '';
      # The Pi 3's boot ROM only reads MBR partition tables
      hybridMbr = true;
    })
    (mkBoard {
      name = "pi4";
      # The BCM2711 family; not only the Pi 4
      description = "BCM2711 boards: Raspberry Pi 4B, 400 and Compute Module 4";
      deviceTree = "broadcom/bcm2711-rpi-4-b.dtb";
      soc = "brcm,bcm2711";
      gpuFirmware = [
        "start4.elf"
        "fixup4.dat"
      ];
      vendorDeviceTrees = [
        "bcm2711-rpi-4-b.dtb"
        "bcm2711-rpi-400.dtb"
        "bcm2711-rpi-cm4.dtb"
      ];
      overlays = [
        "miniuart-bt.dtbo"
        "upstream-pi4.dtbo"
      ];
      # From github.com/pftf/RPi4
      configTxt = ''
        arm_64bit=1
        arm_boost=1
        enable_uart=1
        uart_2ndstage=1
        enable_gic=1
        armstub=RPI_EFI.fd
        disable_commandline_tags=1
        disable_overscan=1
        device_tree_address=0x3e0000
        device_tree_end=0x400000
        dtoverlay=miniuart-bt
        dtoverlay=upstream-pi4
      '';
      # The Pi 4's EEPROM bootloader reads GPT
      hybridMbr = false;
    })
  ];
}
