org 0x7c00
bits 16

start:
    jmp short start_boot
    nop

    ; FAT12 BPB
    db 'PSOS    ' ; OEM Name
    dw 512      ; Bytes per sector
    db 1        ; Sectors per cluster
    dw 1        ; Reserved sectors
    db 2        ; Number of FATs
    dw 224      ; Root directory entries
    dw 2880     ; Total sectors
    db 0xF0     ; Media type
    dw 9        ; Sectors per FAT
    dw 18       ; Sectors per track
    dw 2        ; Number of heads
    dd 0        ; Hidden sectors
    dd 0        ; Total sectors (if > 32MB)
    db 0        ; Drive number
    db 0        ; Reserved
    db 0x29     ; Extended boot signature
    dd 0x12345678 ; Volume serial number
    db 'PSOS BOOT ' ; Volume label
    db 'FAT12   ' ; Filesystem type

start_boot:
    ; Normalise segments so ES:BX and the subsequent far jump are reliable
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; Load stage2 from disk
    mov ah, 0x02 ; Read sectors
    mov al, 4    ; Number of sectors to read
    mov ch, 0    ; Cylinder
    mov cl, 2    ; Sector to start reading from (1 is the boot sector)
    mov dh, 0    ; Head
    ; dl is the drive number, passed by the BIOS
    mov bx, 0x8000 ; ES:BX load address (ES=0 set above)
    int 0x13

    jmp 0x0000:0x8000 ; Far jump to normalise CS=0 before stage2

times 510 - ($ - $$) db 0
dw 0xaa55
