org 0x7c00
bits 16

start:
    ; Load stage2 from disk
    mov ah, 0x02 ; Read sectors
    mov al, 4    ; Number of sectors to read
    mov ch, 0    ; Cylinder
    mov cl, 2    ; Sector to start reading from (1 is the boot sector)
    mov dh, 0    ; Head
    ; dl is the drive number, passed by the BIOS
    mov bx, 0x8000 ; Load address
    int 0x13

    jmp 0x8000 ; Jump to stage2

times 510 - ($ - $$) db 0
dw 0xaa55
