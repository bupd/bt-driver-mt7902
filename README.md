# MediaTek MT7902 (Filogic 310) Bluetooth Driver for Linux

Out-of-tree kernel patches to enable **Bluetooth 5.3** on the MediaTek MT7902 (Filogic 310) combo chip. Tested on ASUS Vivobook 14 with Arch Linux (kernel 6.17.7 / 6.19.8).

## What

Three patches that add MT7902 Bluetooth support to the Linux `btusb` / `btmtk` kernel modules:

| Patch | File | Change |
|-------|------|--------|
| 01 | `btmtk.h` | Adds `FIRMWARE_MT7902` macro for the BT firmware path |
| 02 | `btmtk.c` | Adds `0x7902` to subsystem reset, UDMA clear, and firmware setup switch |
| 03 | `btusb.c` | Adds 4 USB device IDs (`13d3:3579/3580/3594/3596`) with `BTUSB_MEDIATEK` quirk |

## Hardware Information

| Property | Value |
|----------|-------|
| **Chip** | MediaTek MT7902 (Filogic 310) |
| **USB Vendor:Product** | `13d3:3579` (IMC Networks / AzureWave) |
| **Additional USB IDs** | `13d3:3580`, `13d3:3594`, `13d3:3596` |
| **Interface** | USB (integrated in combo WiFi/BT chip) |
| **Bluetooth Standard** | Bluetooth 5.3 |
| **Firmware** | `BT_RAM_CODE_MT7902_1_1_hdr.bin` (509,320 bytes) |
| **Manufacturer** | MediaTek Inc. |

## Why It Doesn't Work Out of the Box

The existing `btusb` module does match the device via a generic vendor wildcard (`13d3:*`), but three things are missing:

1. **No `BTUSB_MEDIATEK` quirk flag** — Without an explicit USB device ID entry in the `quirks_table`, the device is handled as a generic Bluetooth USB device instead of going through the MediaTek-specific `btmtk` code path. This means HCI Reset times out (`Opcode 0x0c03 failed: -110`).

2. **No `case 0x7902:` in btmtk** — Even if the MediaTek code path is reached, `btmtk_usb_setup()` has a switch on the chip's device ID (`0x7902`), which falls through to the `default:` error case returning `-ENODEV`.

3. **Missing firmware** — The BT firmware file `BT_RAM_CODE_MT7902_1_1_hdr.bin` is not shipped with `linux-firmware` packages yet (merged upstream Feb 21, 2026).

These patches have been submitted upstream but haven't landed in stable kernels yet (expected Linux 7.1/7.2). This repo provides a working out-of-tree build until then.

## What the Patches Do

### Patch 01: btmtk.h — Add firmware define
Adds `FIRMWARE_MT7902` macro pointing to `mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin`.

### Patch 02: btmtk.c — Add MT7902 support (4 changes)
1. **`btmtk_usb_subsys_reset()`** — Adds `dev_id == 0x7902` to the MT7922 reset path (same register sequence).
2. **`btmtk_usb_subsys_reset()` post-reset** — Adds MT7902 to the UDMA interrupt status clear after reset.
3. **`btmtk_usb_setup()` switch** — Adds `case 0x7902:` as a fallthrough before `case 0x7922:`, so MT7902 uses the same 79xx firmware loading and initialization path.
4. **`MODULE_FIRMWARE()`** — Declares `FIRMWARE_MT7902` for module metadata.

### Patch 03: btusb.c — Add USB device IDs
Adds four MT7902 USB device ID entries to the `quirks_table` with `BTUSB_MEDIATEK | BTUSB_WIDEBAND_SPEECH` flags:
- `13d3:3579` (primary, used by ASUS Vivobook 14)
- `13d3:3580`
- `13d3:3594`
- `13d3:3596`

## How

### Prerequisites

- Linux kernel 6.17.x+ with headers installed
- GCC and make (build tools)
- Root access

```bash
# Arch Linux
sudo pacman -S linux-headers base-devel

# Ubuntu / Debian
sudo apt install linux-headers-$(uname -r) build-essential

# Fedora
sudo dnf install kernel-devel kernel-headers gcc make
```

### Step 1: Download Firmware

```bash
sudo wget -O /lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin \
  "https://gitlab.com/kernel-firmware/linux-firmware/-/raw/main/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin"
```

| File | Size |
|------|------|
| `BT_RAM_CODE_MT7902_1_1_hdr.bin` | 509,320 bytes |

### Step 2: Build the Modules

The source files (`btmtk.c`, `btmtk.h`, `btusb.c`) are already patched. To build:

```bash
git clone https://github.com/bupd/bt-driver-mt7902.git && cd bt-driver-mt7902

# Build against running kernel headers
make
```

This produces:
- `btusb.ko` — USB Bluetooth driver (with MT7902 device IDs)
- `btmtk.ko` — MediaTek Bluetooth protocol handler (with MT7902 support)

### Step 3: Install the Modules

```bash
MODDIR="/lib/modules/$(uname -r)/kernel/drivers/bluetooth"

# Backup existing modules
mkdir -p backup_modules
cp $MODDIR/btusb.ko.zst $MODDIR/btmtk.ko.zst backup_modules/ 2>/dev/null
cp $MODDIR/btusb.ko $MODDIR/btmtk.ko backup_modules/ 2>/dev/null

# Remove old compressed modules (kernel prefers .ko.zst over .ko)
sudo rm -f $MODDIR/btusb.ko.zst $MODDIR/btmtk.ko.zst

# Install new modules
sudo cp btusb.ko btmtk.ko $MODDIR/

# Regenerate module dependencies
sudo depmod -a
```

### Step 4: Load and Verify

```bash
# Unload old modules
sudo rmmod btusb btmtk

# Load new modules
sudo modprobe btusb

# Verify
bluetoothctl show    # Should show a powered controller
sudo dmesg | grep hci0  # Should show "Device setup in ... usecs"
```

Expected dmesg output:
```
Bluetooth: hci0: HW/SW Version: 0x008a008a, Build Time: 20250826211444
Bluetooth: hci0: Device setup in 3261683 usecs
```

## DKMS Setup (Survive Kernel Updates)

To prevent the driver from breaking on future kernel updates, set up DKMS:

```bash
# Copy source to DKMS directory
sudo mkdir -p /usr/src/mt7902-bt-1.0.0
sudo cp btusb.c btmtk.c btmtk.h btbcm.h btintel.h btrtl.h Makefile \
  /usr/src/mt7902-bt-1.0.0/
```

Create `/usr/src/mt7902-bt-1.0.0/dkms.conf`:
```ini
PACKAGE_NAME="mt7902-bt"
PACKAGE_VERSION="1.0.0"

MAKE="make -C /lib/modules/${kernelver}/build M=${dkms_tree}/${PACKAGE_NAME}/${PACKAGE_VERSION}/build modules"

BUILT_MODULE_NAME[0]="btusb"
BUILT_MODULE_LOCATION[0]=""
DEST_MODULE_LOCATION[0]="/updates/dkms"

BUILT_MODULE_NAME[1]="btmtk"
BUILT_MODULE_LOCATION[1]=""
DEST_MODULE_LOCATION[1]="/updates/dkms"

AUTOINSTALL="yes"
```

Then register, build and install:
```bash
sudo dkms add mt7902-bt/1.0.0
sudo dkms build mt7902-bt/1.0.0
sudo dkms install mt7902-bt/1.0.0 --force
```

## Troubleshooting

### "Opcode 0x0c03 failed: -110"
This means the old (unpatched) btusb module is loaded. Verify the patched module is in use:
```bash
modinfo btmtk | grep MT7902
# Should show: firmware: mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin
```

### Module not auto-loading after reboot
Verify the USB alias exists and depmod has been run:
```bash
modinfo btusb | grep 13d3
# Should show alias entries for the MT7902 USB IDs

sudo depmod -a
```

### Bluetooth pairs but audio doesn't work
The `BTUSB_WIDEBAND_SPEECH` flag is set in the patches, which enables wideband speech (mSBC) for HFP. If audio still fails, check that PulseAudio/PipeWire has the bluetooth module loaded:
```bash
# PipeWire
pactl list modules | grep bluetooth

# PulseAudio
pactl load-module module-bluetooth-discover
```

### Reverting Changes
```bash
MODDIR="/lib/modules/$(uname -r)/kernel/drivers/bluetooth"
sudo rm -f $MODDIR/btusb.ko $MODDIR/btmtk.ko
sudo cp backup_modules/btusb.ko.zst backup_modules/btmtk.ko.zst $MODDIR/
sudo depmod -a
sudo rmmod btusb btmtk
sudo modprobe btusb
```

## Upstream Status

- **Kernel patch**: Submitted by OnlineLearningTutorials (Kush Kulshrestha) on Feb 14, 2026 — under review on LKML
- **Firmware**: Committed to linux-firmware by Sean Wang (MediaTek) on Feb 21, 2026 (commit `df954d2`)
- **Expected mainline**: Linux 7.1 or 7.2

Once these patches land in a stable kernel release, this out-of-tree module will no longer be needed.

## Tested Configuration

| Component | Version |
|-----------|---------|
| **Laptop** | ASUS Vivobook 14 |
| **Kernel** | 6.17.7-arch1-2, 6.19.8-arch1-1 |
| **OS** | Arch Linux |
| **BT USB Device** | `13d3:3579` (IMC Networks Wireless_Device) |
| **Firmware** | Build 20250826211444 (509,320 bytes) |
| **Result** | Controller powered on, Bluetooth 5.3 operational |

## WiFi Driver

The MT7902 is a combo WiFi/Bluetooth chip. For WiFi support, see the companion repo: [wifi-driver-mt7902](https://github.com/bupd/wifi-driver-mt7902)

## License

The btusb/btmtk drivers are licensed under GPL-2.0/ISC. All patches follow the same licensing.
