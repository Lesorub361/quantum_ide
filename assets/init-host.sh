#!/bin/sh
# init-host.sh - Wrapper to launch proot with correct paths

FILES_DIR="$1"
if [ -z "$FILES_DIR" ]; then
    # Fallback to current directory if not provided
    FILES_DIR=$(pwd)
fi

PROOT="$FILES_DIR/bin/proot"
ROOTFS="$FILES_DIR/ubuntu"
TMPDIR="$FILES_DIR/runtime/tmp"

# Ensure tmp dir exists
mkdir -p "$TMPDIR"

# Set up environment for proot
export PROOT_TMP_DIR="$TMPDIR"
export LD_LIBRARY_PATH="$FILES_DIR"

# Launch proot
# -S: bind-mount rootfs and use it as /
# -0: fake root id
# -b: bind mounts
# -w: working directory
# -q: qemu (if needed, but here we assume native)

"$PROOT" \
    -S "$ROOTFS" \
    -0 \
    -b /dev \
    -b /proc \
    -b /sys \
    -b /dev/pts \
    -b "$FILES_DIR/bin:/usr/local/bin" \
    -w /root \
    /bin/bash --login
