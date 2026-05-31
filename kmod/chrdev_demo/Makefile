# Kbuild-style out-of-tree module Makefile.
#
# On the board (recommended — simplest):
#   make
# This uses /lib/modules/$(uname -r)/build, which must be present
# (i.e. the board image was built with kernel headers shipped).
#
# Cross-compiling from the host (zig as CC works, but kbuild needs
# both CC and LD; easiest is to point at the same toolchain used to
# build the kernel):
#   make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
#        KDIR=/path/to/stm32mp157-kernel-source

obj-m := chrdev_demo.o

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

.PHONY: all clean
