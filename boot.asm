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

; Write a single character directly to VGA text mode (0xB800:offset).
; Uses GS as the VGA segment — set once at the top of start_boot and
; left alone so it can be used anywhere without disturbing DS/ES.
; Attribute 0x4F = white text on red background (hard to miss).
%macro trace 2          ; trace char, vga_byte_offset
    mov byte [gs:%2],   %1
    mov byte [gs:%2+1], 0x4F
%endmacro

start_boot:
    ; Point GS at the VGA text buffer for debug breadcrumbs.
    mov ax, 0xB800
    mov gs, ax
    trace '?', 0        ; '?' = we reached start_boot

    ; Normalise segments and establish an explicit stack.
    ; Loading SS inhibits interrupts for the following instruction (SP load),
    ; guaranteeing an atomic SS:SP update.
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00      ; stack grows down from boot sector base

    trace '1', 2        ; '1' = segments + stack set up

    ; --- E820 memory map query ---
    ; Layout: dword entry count at 0x500, then 24-byte entries from 0x504.
    ; 24 bytes = 8 (base) + 8 (length) + 4 (type) + 4 (ACPI 3.0 attrs).
    ; Must be done in real mode before the protected-mode switch.
    ; Buffer capacity: (0x7C00 - 0x504) / 24 = 1269 max; cap at 128 for safety.
    push dx                 ; save boot drive number: the loop sets EDX=0x534D4150
                            ; (DL='P') on every iteration, clobbering DL before int 0x13
    mov dword [0x500], 0    ; initialise entry count
    mov di, 0x504           ; ES:DI = 0x0000:0x504 (ES=0 set above)
    xor ebx, ebx            ; EBX=0 starts the E820 enumeration
    trace '2', 4        ; '2' = about to call int 0x15/E820

.e820_loop:
    cmp dword [0x500], 128  ; cap at 128 entries to protect the boot sector
    jae .e820_done
    mov eax, 0xE820
    mov ecx, 24             ; request 24-byte (ACPI 3.0) entries
    mov edx, 0x534D4150     ; signature 'SMAP'
    int 0x15
    jc .e820_done           ; carry set: end of list or unsupported
    cmp eax, 0x534D4150     ; BIOS must echo 'SMAP' back in EAX
    jne .e820_done
    inc dword [0x500]       ; one more valid entry
    add di, 24              ; advance buffer pointer
    test ebx, ebx           ; EBX=0 after last entry
    jnz .e820_loop

.e820_done:
    trace '3', 6        ; '3' = E820 done, about to load stage2

    ; Re-zero AX and ES: the BIOS E820 handler may have clobbered them.
    xor ax, ax
    mov es, ax
    pop dx                  ; restore boot drive number (saved before E820 loop)

    ; Load stage2 from disk
    mov ah, 0x02 ; Read sectors
    mov al, 4    ; Number of sectors to read
    mov ch, 0    ; Cylinder
    mov cl, 2    ; Sector to start reading from (1 is the boot sector)
    mov dh, 0    ; Head
    ; dl = boot drive number, restored above
    mov bx, 0x8000 ; ES:BX load address (ES=0 set above)
    int 0x13
    trace '4', 8        ; '4' = int 0x13 returned (stage2 should be loaded)

    jmp 0x0000:0x8000 ; Far jump to normalise CS=0 before stage2

times 510 - ($ - $$) db 0
dw 0xaa55
