#!/bin/bash

# Exit on error
set -e

# 1. Clean up old files
echo "Cleaning up old files..."
rm -f boot.bin stage2.bin psos.img

# 2. Build PSOS components
echo "Building PSOS components..."
nasm -f bin boot.asm -o boot.bin
nasm -f bin stage2.asm -o stage2.bin

# 3. Combine components into a single image
cat boot.bin stage2.bin > psos.img

# 4. Run in QEMU
echo "Booting PSOS in QEMU..."
qemu-system-x86_64 -k en-gb -drive file=psos.img,format=raw,if=floppy
