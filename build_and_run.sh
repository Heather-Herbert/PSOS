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

# 3. Create a 1.44MB floppy image
echo "Creating floppy image..."
dd if=/dev/zero of=psos.img bs=1024 count=1440

# 4. Format the image as FAT12
echo "Formatting image as FAT12..."
mkfs.fat -F 12 psos.img

# 5. Write the bootloader to the image
echo "Writing bootloader to image..."
dd if=boot.bin of=psos.img conv=notrunc

# 6. Write stage2 to the image
echo "Writing stage2 to image..."
dd if=stage2.bin of=psos.img seek=1 bs=512 conv=notrunc

# 7. Run in QEMU
echo "Booting PSOS in QEMU..."
qemu-system-x86_64 -k en-gb -drive file=psos.img,format=raw
