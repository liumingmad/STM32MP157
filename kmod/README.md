# STM32MP157 Driver Development

This directory holds out-of-tree Linux driver demos for the Alientek
STM32MP157 board.

The board currently reports:

```text
Linux 5.4.31-g886e225be armv7l
```

Use OrbStack/Docker from the repository root:

```sh
make driver-image
make driver-prepare-stable
make driver-build
```

`driver-prepare-stable` downloads vanilla `linux-5.4.31` from kernel.org into
the Docker volume `stm32mp157-kernel-5.4.31`, copies
`kmod/kernel-info/config` into `.config`, and runs the kernel
`prepare/modules_prepare` steps with `LOCALVERSION=-g886e225be`. The kernel
tree intentionally lives in a Docker volume because the Linux source tree has
case-sensitive paths that are unsafe on the default macOS filesystem.

For production driver work, prefer the exact Alientek kernel source tree and
matching `Module.symvers` from the image that produced the board kernel. The
board has `CONFIG_MODVERSIONS=y`; without the exact symbol versions, a module
can compile but still fail to load.

To use an exact kernel tree instead of the prepared stable tree, mount it with
`KDIR_HOST`:

```sh
KDIR_HOST=/absolute/path/to/linux-5.4.31 \
KDIR_CONTAINER=/kernel \
scripts/driver-dev.sh build
```
