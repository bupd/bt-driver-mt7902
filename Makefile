# SPDX-License-Identifier: GPL-2.0
#
# Out-of-tree Makefile for btusb + btmtk with MT7902 support
#

KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build

obj-m += btusb.o btmtk.o

# Replicate the Kconfig defines the in-tree build sets
ccflags-y += -DCONFIG_BT_HCIBTUSB_MTK
ccflags-y += -DCONFIG_BT_MTK_MODULE

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
