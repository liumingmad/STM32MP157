#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${STM32MP157_DRIVER_IMAGE:-stm32mp157-driver-dev:ubuntu20.04}"
KERNEL_VERSION="${KERNEL_VERSION:-5.4.31}"
LOCALVERSION="${LOCALVERSION:--g886e225be}"
KERNEL_VOLUME="${KERNEL_VOLUME:-stm32mp157-kernel-$KERNEL_VERSION}"
KDIR_HOST="${KDIR_HOST:-}"
KDIR_CONTAINER="${KDIR_CONTAINER:-/kernel-src/linux-$KERNEL_VERSION}"
MODULE_DIR="/work/kmod/chrdev_demo"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"

usage() {
    cat <<EOF
usage: $0 <command>

commands:
  build-image       Build the OrbStack/Docker development image
  prepare-stable    Download linux-$KERNEL_VERSION from kernel.org and prepare headers
  build             Build kmod/chrdev_demo/chrdev_demo.ko
  clean             Clean chrdev_demo module build outputs
  shell             Open an interactive shell in the development container

environment:
  STM32MP157_DRIVER_IMAGE  Docker image tag (default: $IMAGE)
  KERNEL_VERSION           Kernel base version (default: $KERNEL_VERSION)
  LOCALVERSION             Kernel localversion (default: $LOCALVERSION)
  KERNEL_VOLUME            Docker volume for kernel tree (default: $KERNEL_VOLUME)
  KDIR_HOST                Optional exact host kernel tree path
  KDIR_CONTAINER           Container kernel tree path (default: $KDIR_CONTAINER)
  JOBS                     Parallel make jobs (default: $JOBS)
EOF
}

docker_run() {
    local mount_args
    if [ -n "$KDIR_HOST" ]; then
        mount_args=(-v "$KDIR_HOST:$KDIR_CONTAINER")
    else
        mount_args=(-v "$KERNEL_VOLUME:/kernel-src")
    fi
    docker run --rm \
        --platform linux/arm64 \
        -e "KERNEL_VERSION=$KERNEL_VERSION" \
        -e "LOCALVERSION=$LOCALVERSION" \
        -e "KDIR_CONTAINER=$KDIR_CONTAINER" \
        -e "JOBS=$JOBS" \
        "${mount_args[@]}" \
        -v "$ROOT:/work" \
        -w /work \
        "$IMAGE" "$@"
}

docker_shell() {
    local mount_args
    if [ -n "$KDIR_HOST" ]; then
        mount_args=(-v "$KDIR_HOST:$KDIR_CONTAINER")
    else
        mount_args=(-v "$KERNEL_VOLUME:/kernel-src")
    fi
    docker run --rm -it \
        --platform linux/arm64 \
        -e "KERNEL_VERSION=$KERNEL_VERSION" \
        -e "LOCALVERSION=$LOCALVERSION" \
        -e "KDIR_CONTAINER=$KDIR_CONTAINER" \
        -e "JOBS=$JOBS" \
        "${mount_args[@]}" \
        -v "$ROOT:/work" \
        -w /work \
        "$IMAGE" bash
}

build_image() {
    docker build \
        -f "$ROOT/docker/stm32mp157-driver/Dockerfile" \
        -t "$IMAGE" \
        "$ROOT"
}

prepare_stable() {
    docker_run bash -lc '
        set -euo pipefail
        mkdir -p "$(dirname "$KDIR_CONTAINER")"
        if [ ! -d "$KDIR_CONTAINER" ]; then
            tmp="/tmp/linux-$KERNEL_VERSION.tar.xz"
            curl -fL "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$KERNEL_VERSION.tar.xz" -o "$tmp"
            tar -C "$(dirname "$KDIR_CONTAINER")" -xf "$tmp"
        fi

        cp /work/kmod/kernel-info/config "$KDIR_CONTAINER/.config"
        make -C "$KDIR_CONTAINER" \
            ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LOCALVERSION="$LOCALVERSION" \
            olddefconfig
        make -C "$KDIR_CONTAINER" \
            ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LOCALVERSION="$LOCALVERSION" \
            prepare modules_prepare scripts -j "$JOBS"
        make -C "$KDIR_CONTAINER" \
            ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LOCALVERSION="$LOCALVERSION" \
            kernelrelease
    '
}

build_module() {
    docker_run bash -lc '
        set -euo pipefail
        if [ ! -d "$KDIR_CONTAINER" ]; then
            echo "missing kernel tree: $KDIR_CONTAINER" >&2
            echo "run: scripts/driver-dev.sh prepare-stable" >&2
            echo "or set KDIR_HOST/KDIR_CONTAINER to your exact Alientek kernel source tree." >&2
            exit 1
        fi
        make -C "$KDIR_CONTAINER" M="'"$MODULE_DIR"'" \
            ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LOCALVERSION="$LOCALVERSION" \
            modules
        file /work/kmod/chrdev_demo/chrdev_demo.ko
        modinfo /work/kmod/chrdev_demo/chrdev_demo.ko | sed -n "1,30p"
    '
}

clean_module() {
    docker_run bash -lc '
        if [ ! -d "$KDIR_CONTAINER" ]; then
            rm -f /work/kmod/chrdev_demo/*.o \
                  /work/kmod/chrdev_demo/*.ko \
                  /work/kmod/chrdev_demo/*.mod \
                  /work/kmod/chrdev_demo/*.mod.c \
                  /work/kmod/chrdev_demo/Module.symvers \
                  /work/kmod/chrdev_demo/modules.order
            exit 0
        fi
        make -C "$KDIR_CONTAINER" M="'"$MODULE_DIR"'" \
            ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LOCALVERSION="$LOCALVERSION" \
            clean
    '
}

cmd="${1:-}"
case "$cmd" in
    build-image) build_image ;;
    prepare-stable) prepare_stable ;;
    build) build_module ;;
    clean) clean_module ;;
    shell) docker_shell ;;
    -h|--help|help|"") usage ;;
    *) echo "unknown command: $cmd" >&2; usage >&2; exit 2 ;;
esac
