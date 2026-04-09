# MediaTek MT7902 Bluetooth Driver for Linux

Out-of-tree kernel patches to enable **Bluetooth 5.3** on the MediaTek MT7902 (Filogic 310) combo chip. Tested on ASUS Vivobook 14 with Arch Linux (kernel 6.17.7 / 6.19.8).

## What

Three patches that add MT7902 Bluetooth support to the Linux `btusb` / `btmtk` kernel modules:

| Patch | File | Change |
|-------|------|--------|
| 01 | `btmtk.h` | Adds `FIRMWARE_MT7902` macro for the BT firmware path |
| 02 | `btmtk.c` | Adds `0x7902` to subsystem reset, UDMA clear, and firmware setup switch |
| 03 | `btusb.c` | Adds 4 USB device IDs (`13d3:3579/3580/3594/3596`) with `BTUSB_MEDIATEK` quirk |

**Hardware:** USB `13d3:3579` (IMC Networks) · Bluetooth 5.3 · Firmware: `BT_RAM_CODE_MT7902_1_1_hdr.bin` (509 KB)

## Why

The MT7902's Bluetooth interface is detected as a generic USB device, but without the `BTUSB_MEDIATEK` quirk flag the MediaTek-specific initialization code in `btmtk` is never called. HCI Reset times out (`Opcode 0x0c03 failed: -110`) and the controller stays dead. These patches have been submitted upstream but haven't landed in stable kernels yet (expected Linux 7.1/7.2).

## How

### 1. Install firmware

```bash
sudo wget -O /lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin \
  "https://gitlab.com/kernel-firmware/linux-firmware/-/raw/main/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin"
```

### 2. Build

```bash
git clone https://github.com/bupd/bt-driver-mt7902.git && cd bt-driver-mt7902
make   # builds btusb.ko and btmtk.ko
```

### 3. Install

```bash
MODDIR="/lib/modules/$(uname -r)/kernel/drivers/bluetooth"

# Backup originals
mkdir -p backup_modules
cp $MODDIR/btusb.ko.zst $MODDIR/btmtk.ko.zst backup_modules/ 2>/dev/null

# Replace
sudo rm -f $MODDIR/btusb.ko.zst $MODDIR/btmtk.ko.zst
sudo cp btusb.ko btmtk.ko $MODDIR/
sudo depmod -a
```

### 4. Load

```bash
sudo rmmod btusb btmtk 2>/dev/null
sudo modprobe btusb
bluetoothctl show   # should show a powered controller
```

### Verify

```bash
# dmesg should show:
# Bluetooth: hci0: Device setup in ... usecs
sudo dmesg | grep hci0
```

### Revert

```bash
MODDIR="/lib/modules/$(uname -r)/kernel/drivers/bluetooth"
sudo rm -f $MODDIR/btusb.ko $MODDIR/btmtk.ko
sudo cp backup_modules/* $MODDIR/
sudo depmod -a && sudo rmmod btusb btmtk && sudo modprobe btusb
```

## Upstream Status

- **Kernel patch**: Submitted Feb 14, 2026 — under review on LKML
- **Firmware**: Merged to linux-firmware Feb 21, 2026 (commit `df954d2`)
- **Expected mainline**: Linux 7.1 or 7.2

## License

GPL-2.0 / ISC (same as upstream btusb/btmtk)
