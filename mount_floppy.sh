#!/bin/bash
# mount_floppy.sh - Script to mount a disk image as a temporary floppy disk.

# --- Configuration ---
# The name of your floppy disk image file.
IMAGE_FILE="floppy.img"

# The temporary directory where the image will be mounted.
MOUNT_POINT="/tmp/floppy_mnt"

# --- Main Logic ---

echo "--- Floppy Image Mounter ---"

# 1. Check if the disk image file exists in the current directory
if [ ! -f "$IMAGE_FILE" ]; then
    echo "Error: Disk image file '$IMAGE_FILE' not found."
    echo "Please ensure the file is in the current directory."
    exit 1
fi

# 2. Create the mount point if it doesn't exist
if [ ! -d "$MOUNT_POINT" ]; then
    echo "Creating temporary mount point: $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"
fi

# 3. Perform the mount operation
# The '-o loop' option is essential for mounting a file as a block device.
echo "Attempting to mount '$IMAGE_FILE' to '$MOUNT_POINT'..."
# Note: 'mount' often requires 'sudo'. Run this script as 'sudo ./mount_floppy.sh'
if mount -o loop "$IMAGE_FILE" "$MOUNT_POINT"; then
    echo ""
    echo "---------------------------------------------------------"
    echo "SUCCESS: '$IMAGE_FILE' mounted successfully!"
    echo "Access your files here: $MOUNT_POINT"
    echo "---------------------------------------------------------"
    echo "REMINDER: To UNMOUNT, run the following command:"
    echo "sudo umount $MOUNT_POINT"
    echo "---------------------------------------------------------"
else
    echo ""
    echo "Error: Mount failed."
    echo "Possible issues:"
    echo "  - You must run this script using 'sudo'."
    echo "  - The image file '$IMAGE_FILE' may be corrupt or have an unknown filesystem."
    exit 1
fi

# Cleanup: remove the temporary mount point if it's empty after failure
if [ $? -ne 0 ] && [ -d "$MOUNT_POINT" ] && [ ! "$(ls -A "$MOUNT_POINT")" ]; then
    rmdir "$MOUNT_POINT"
fi

exit 0
