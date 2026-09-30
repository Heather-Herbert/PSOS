; Shared build configuration for boot.asm and stage2.asm.

; Number of 512-byte sectors reserved for stage2, starting at LBA 1.
; The boot sector plus stage2 make up the FAT12 reserved region, so the
; BPB's reserved sector count is STAGE2_SECTORS + 1 and the first FAT
; starts immediately after stage2. build_and_run.sh passes the same
; reserved count to mkfs.fat.
; Must be <= 17 so the whole of stage2 is read from track 0, head 0
; (18 sectors per track, boot sector occupies sector 1).
STAGE2_SECTORS equ 16
RESERVED_SECTORS equ STAGE2_SECTORS + 1
