#!/bin/sh
# init-host.sh - Wrapper to launch proot with correct paths and Android 14+ compatibility

FILES_DIR="$1"
if [ -z "$FILES_DIR" ]; then
    FILES_DIR=$(pwd)
fi

PROOT="$FILES_DIR/bin/proot"
ROOTFS="$FILES_DIR/rootfs/ubuntu"
if [ ! -d "$ROOTFS" ] && [ -d "$FILES_DIR/ubuntu" ]; then
    ROOTFS="$FILES_DIR/ubuntu"
fi
TMPDIR="$FILES_DIR/runtime/tmp"

mkdir -p "$TMPDIR"

export PROOT_TMP_DIR="$TMPDIR"
export PROOT_NO_SECCOMP=1
export LD_LIBRARY_PATH="$FILES_DIR:$FILES_DIR/bin:${LD_LIBRARY_PATH:-}"

SDCARD_BIND=""
if [ -d "/storage/emulated/0" ]; then
    SDCARD_BIND="-b /storage/emulated/0:/sdcard"
fi

"$PROOT" \
    --link2symlink \
    -0 \
    -r "$ROOTFS" \
    -b /dev \
    -b /proc \
    -b /sys \
    -b /dev/pts \
    $SDCARD_BIND \
    -b "$FILES_DIR/bin:/usr/local/bin" \
    -w /root \
    /bin/bash --login
