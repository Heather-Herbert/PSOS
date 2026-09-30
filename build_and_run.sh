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
# Reserve the boot sector plus stage2's sectors so the FATs start after
# stage2 instead of being overwritten by it. Must match RESERVED_SECTORS
# in config.inc (which boot.asm writes into the BPB).
STAGE2_SECTORS=$(awk '/^STAGE2_SECTORS[[:space:]]+equ/ {print $3}' config.inc)
RESERVED_SECTORS=$((STAGE2_SECTORS + 1))
echo "Formatting image as FAT12 ($RESERVED_SECTORS reserved sectors)..."
mkfs.fat -F 12 -R "$RESERVED_SECTORS" psos.img

# 5. Write the bootloader to the image
echo "Writing bootloader to image..."
dd if=boot.bin of=psos.img conv=notrunc

# 6. Write stage2 to the image
echo "Writing stage2 to image..."
dd if=stage2.bin of=psos.img seek=1 bs=512 conv=notrunc

# 7. Run in QEMU
# The image is attached as an IDE hard disk (not a floppy) because
# stage2's disk driver talks to the primary ATA controller.
# -no-reboot  : freeze on triple fault instead of reset-looping
# -monitor stdio : type 'info registers' in this terminal when hung
echo "Booting PSOS in QEMU..."
echo "Tip: type 'info registers' here when the screen hangs"
echo "     interrupt log written to /tmp/qemu.log"
qemu-system-x86_64 -k en-gb -drive file=psos.img,format=raw,if=ide,index=0 \
    -no-reboot -monitor stdio \
    -d int -D /tmp/qemu.log
