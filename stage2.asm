bits 16
org 0x8000

start_stage2:
    ; Ensure DS=0 so that lgdt reads the GDT descriptor from the correct
    ; physical address. If DS is non-zero the CPU loads a garbage GDTR and
    ; the subsequent far jump triple-faults.
    xor ax, ax
    mov ds, ax

    cli
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, 0x1
    mov cr0, eax
    jmp 0x08:protected_mode

bits 32
protected_mode:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, stack_top

    call pic_remap
    call idt_setup
    lidt [idt_descriptor]
    sti

    mov edi, 0xb8000
    mov ecx, 80 * 25
    mov al, ' '
    mov ah, 0x17
    rep stosw

    call print_e820_map

    mov edi, (5 * 80 + 25) * 2
    mov esi, ascii_art_line1
    call print_string_pm
    mov edi, (6 * 80 + 25) * 2
    mov esi, ascii_art_line2
    call print_string_pm
    mov edi, (7 * 80 + 25) * 2
    mov esi, ascii_art_line3
    call print_string_pm
    mov edi, (8 * 80 + 25) * 2
    mov esi, ascii_art_line4
    call print_string_pm
    mov edi, (9 * 80 + 25) * 2
    mov esi, ascii_art_line5
    call print_string_pm
    mov edi, (10 * 80 + 25) * 2
    mov esi, ascii_art_line6
    call print_string_pm
    mov edi, (11 * 80 + 25) * 2
    mov esi, ascii_art_line7
    call print_string_pm

    call cli_main

halt:
    hlt

msg_test_pass db 'PASS', 0
msg_test_fail db 'FAIL', 0
msg_test_write_pass db 'WRITE PASS', 0
msg_test_write_fail db 'WRITE FAIL', 0

test_read_boot_sector:
    ; Test if the boot sector is read correctly.
    ; It checks if BytesPerSec is 512.
    movzx eax, word [boot_sector + fat12_bpb.BPB_BytsPerSec]
    cmp eax, 512
    je .pass
.fail:
    mov esi, msg_test_fail
    call print_string_pm
    ret
.pass:
    mov esi, msg_test_pass
    call print_string_pm
    ret

test_disk_write:
    ; Test writing to disk.
    ; 1. Read sector 10 into buffer.
    ; 2. Modify buffer.
    ; 3. Write sector 10.
    ; 4. Read sector 10 into a different buffer (or same, clearing it first).
    ; 5. Verify modification.

    ; Use cluster_buffer for this test.
    
    ; Step 1: Read Sector 10
    mov eax, 10
    mov edi, cluster_buffer
    call ata_read_sector
    jc .fail

    ; Step 2: Modify buffer (first dword)
    mov dword [cluster_buffer], 0xDEADBEEF

    ; Step 3: Write Sector 10
    mov eax, 10
    mov esi, cluster_buffer
    call ata_write_sector
    jc .fail

    ; Step 4: Clear buffer to ensure we are reading fresh data
    mov dword [cluster_buffer], 0

    ; Step 5: Read Sector 10 again
    mov eax, 10
    mov edi, cluster_buffer
    call ata_read_sector
    jc .fail

    ; Step 6: Verify
    cmp dword [cluster_buffer], 0xDEADBEEF
    je .pass

.fail:
    mov esi, msg_test_write_fail
    call print_string_pm
    ret

.pass:
    mov esi, msg_test_write_pass
    call print_string_pm
    ret

run_tests:
    call fat_read_file

    ; Print the first byte of the boot sector
    mov al, [boot_sector]
    movzx eax, al
    mov edi, (21 * 80 + 0) * 2 ; New line
    call print_hex

    jc .error ; Now check the carry flag

    mov edi, (20 * 80 + 0) * 2
    call test_read_boot_sector

    mov edi, (22 * 80 + 0) * 2
    call test_disk_write
    ret

.error:
    mov edi, (20 * 80 + 0) * 2
    mov esi, msg_test_fail
    call print_string_pm
    ret

cli_main:
    mov edi, (14 * 80 + 0) * 2
    mov esi, msg_prompt
    call print_string_pm

    call run_tests

    jmp halt

print_string_pm:
    mov ebx, 0xb8000
.loop:
    lodsb
    cmp al, 0
    je .done
    mov [ebx + edi], al
    mov byte [ebx + edi + 1], 0x17
    add edi, 2
    jmp .loop
.done:
    ret

keyboard_isr:
    pusha
    in al, 0x60

    cmp al, 0x2A
    je .shift_press
    cmp al, 0x36
    je .shift_press
    cmp al, 0xAA
    je .shift_release
    cmp al, 0xB6
    je .shift_release

    cmp al, 0x80
    jae .isr_done

    movzx ebx, al
    cmp byte [shift_pressed], 1
    jne .no_shift

.do_shift:
    add ebx, 128

.no_shift:
    mov al, [scancode_map + ebx]

    cmp al, 0
    je .isr_done
    
    ; This is where we would add the character to a buffer
    ; For now, we just print it to a fixed location.
    mov edi, (14 * 80 + 2) * 2
    mov [0xb8000 + edi], al
    jmp .isr_done

.shift_press:
    mov byte [shift_pressed], 1
    jmp .isr_done
.shift_release:
    mov byte [shift_pressed], 0

.isr_done:
    mov al, 0x20
    out 0x20, al
    popa
    iret

pic_remap:
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    mov al, 0b11111101
    out 0x21, al
    mov al, 0b11111111
    out 0xA1, al
    ret

idt_setup:
    mov eax, keyboard_isr
    mov word [idt + 0x21 * 8], ax
    shr eax, 16
    mov word [idt + 0x21 * 8 + 6], ax
    mov word [idt + 0x21 * 8 + 2], 0x08
    mov byte [idt + 0x21 * 8 + 5], 0x8E
    ret

to_hex_char:
    cmp al, 10
    jl .is_digit
    add al, 'A' - 10
    ret
.is_digit:
    add al, '0'
    ret

; --- E820 memory map (written by boot.asm before PM switch) ---
E820_COUNT   equ 0x500   ; dword: number of entries
E820_ENTRIES equ 0x504   ; array of 24-byte entries:
                         ;   +0  qword base address
                         ;   +8  qword length
                         ;   +16 dword type (1=usable,2=reserved,3=ACPI,4=NVS,5=bad)
                         ;   +20 dword ACPI 3.0 extended attributes

; print_e820_map
; Reads the E820 map left by the bootloader and prints each entry to VGA.
; Rows 0..(count-1), format: "BASE=XXXXXXXX LEN=XXXXXXXX TYPE=X"
; Clobbers: eax, ebx, ecx, edx, esi, edi
print_e820_map:
    mov ecx, [E820_COUNT]
    test ecx, ecx
    jz .done

    mov ebx, E820_ENTRIES   ; pointer to current entry
    xor edx, edx            ; row counter

.entry_loop:
    ; Print "BASE=XXXXXXXX LEN=XXXXXXXX TYPE=XXXXXXXX"
    ; edi is the VGA byte offset; print_string_pm advances it,
    ; but print_hex uses pushad/popad so edi must be manually advanced
    ; by 8*2=16 after each print_hex call.
    mov edi, edx
    imul edi, 80 * 2        ; start of row

    mov esi, msg_e820_base
    call print_string_pm    ; edi now past "BASE="
    mov eax, [ebx]          ; base low 32 bits
    call print_hex
    add edi, 8 * 2          ; advance past 8 hex digits

    mov esi, msg_e820_len
    call print_string_pm    ; edi now past " LEN="
    mov eax, [ebx + 8]      ; length low 32 bits
    call print_hex
    add edi, 8 * 2

    mov esi, msg_e820_type
    call print_string_pm    ; edi now past " TYPE="
    mov eax, [ebx + 16]     ; type
    call print_hex

    inc edx
    add ebx, 24
    loop .entry_loop

.done:
    ret

msg_e820_base db 'BASE=', 0
msg_e820_len  db ' LEN=', 0
msg_e820_type db ' TYPE=', 0

; FAT12 Boot Sector Structure
struc fat12_bpb
    .BS_jmpBoot         resb 3
    .BS_OEMName         resb 8
    .BPB_BytsPerSec     resw 1
    .BPB_SecPerClus     resb 1
    .BPB_RsvdSecCnt     resw 1
    .BPB_NumFATs        resb 1
    .BPB_RootEntCnt     resw 1
    .BPB_TotSec16       resw 1
    .BPB_Media          resb 1
    .BPB_FATSz16        resw 1
    .BPB_SecPerTrk      resw 1
    .BPB_NumHeads       resw 1
    .BPB_HiddSec        resd 1
    .BPB_TotSec32       resd 1
    .BS_DrvNum          resb 1
    .BS_Reserved1       resb 1
    .BS_BootSig         resb 1
    .BS_VolID           resd 1
    .BS_VolLab          resb 11
    .BS_FilSysType      resb 8
endstruc

; ATA PIO Port Definitions
ATA_PRIMARY_DATA equ 0x1F0
ATA_PRIMARY_ERROR equ 0x1F1
ATA_PRIMARY_SECTOR_COUNT equ 0x1F2
ATA_PRIMARY_LBA_LOW equ 0x1F3
ATA_PRIMARY_LBA_MID equ 0x1F4
ATA_PRIMARY_LBA_HIGH equ 0x1F5
ATA_PRIMARY_DRIVE_HEAD equ 0x1F6
ATA_PRIMARY_COMMAND equ 0x1F7
ATA_PRIMARY_STATUS equ 0x1F7

ata_read_sector:
    ; Reads a single sector from the disk using PIO mode.
    ; eax: LBA of the sector to read
    ; edi: memory address to store the sector
    ; returns: carry flag set on error

    ; eax has the LBA.
    ; edi has the buffer.

    ; Save LBA
    push eax

    ; Send head and high 4 bits of LBA
    mov dx, ATA_PRIMARY_DRIVE_HEAD
    shr eax, 24
    or al, 0xE0 ; Master drive, LBA mode
    out dx, al

    ; Restore LBA
    pop eax

    ; Send sector count (save/restore eax so al is not clobbered before LBA_LOW)
    push eax
    mov dx, ATA_PRIMARY_SECTOR_COUNT
    mov al, 1
    out dx, al
    pop eax

    ; Send LBA low, mid, high
    mov dx, ATA_PRIMARY_LBA_LOW
    out dx, al          ; al = LBA[7:0]
    shr eax, 8
    mov dx, ATA_PRIMARY_LBA_MID
    out dx, al          ; al = LBA[15:8]
    shr eax, 8
    mov dx, ATA_PRIMARY_LBA_HIGH
    out dx, al          ; al = LBA[23:16]

    ; Send read command
    mov dx, ATA_PRIMARY_COMMAND
    mov al, 0x20
    out dx, al

    ; Wait for the drive to be ready
    mov ecx, 1000000
.poll_status:
    dec ecx
    jz .timeout

    mov dx, ATA_PRIMARY_STATUS
    in al, dx

    test al, 0x80 ; BSY bit
    jnz .poll_status

    test al, 0x01 ; ERR bit
    jnz .error

    test al, 0x08 ; DRQ bit
    jz .poll_status

    jmp .read_data

.timeout:
    stc ; Set carry flag to indicate timeout
    ret

.error:
    stc ; Set carry flag to indicate error
    ret

.read_data:
    ; Read the sector data
    mov ecx, 256
    mov dx, ATA_PRIMARY_DATA
    rep insw

    clc ; Clear carry flag to indicate success
    ret

ata_write_sector:
    ; Writes a single sector to the disk using PIO mode.
    ; eax: LBA of the sector to write
    ; esi: memory address of the data to write
    ; returns: carry flag set on error

    ; Save LBA
    push eax

    ; Send head and high 4 bits of LBA
    mov dx, ATA_PRIMARY_DRIVE_HEAD
    shr eax, 24
    or al, 0xE0 ; Master drive, LBA mode
    out dx, al

    ; Restore LBA
    pop eax

    ; Send sector count (save/restore eax so al is not clobbered before LBA_LOW)
    push eax
    mov dx, ATA_PRIMARY_SECTOR_COUNT
    mov al, 1
    out dx, al
    pop eax

    ; Send LBA low, mid, high
    mov dx, ATA_PRIMARY_LBA_LOW
    out dx, al          ; al = LBA[7:0]
    shr eax, 8
    mov dx, ATA_PRIMARY_LBA_MID
    out dx, al          ; al = LBA[15:8]
    shr eax, 8
    mov dx, ATA_PRIMARY_LBA_HIGH
    out dx, al          ; al = LBA[23:16]

    ; Send write command
    mov dx, ATA_PRIMARY_COMMAND
    mov al, 0x30 ; Write Sectors
    out dx, al

    ; Wait for the drive to be ready
    mov ecx, 1000000
.poll_status:
    dec ecx
    jz .timeout

    mov dx, ATA_PRIMARY_STATUS
    in al, dx

    test al, 0x80 ; BSY bit
    jnz .poll_status

    test al, 0x01 ; ERR bit
    jnz .error

    test al, 0x08 ; DRQ bit
    jz .poll_status

    jmp .write_data

.timeout:
    stc ; Set carry flag to indicate timeout
    ret

.error:
    stc ; Set carry flag to indicate error
    ret

.write_data:
    ; Write the sector data
    mov ecx, 256
    mov dx, ATA_PRIMARY_DATA
    rep outsw

    ; Flush cache / wait for completion
    ; (Ideally we should poll BSY again or use Cache Flush command 0xE7)
    ; For simple PIO write, waiting for BSY to clear is usually enough.
    mov ecx, 1000000
.poll_finish:
    dec ecx
    jz .timeout_finish
    mov dx, ATA_PRIMARY_STATUS
    in al, dx
    test al, 0x80 ; BSY
    jnz .poll_finish
    test al, 0x01 ; ERR
    jnz .error

    clc
    ret

.timeout_finish:
    stc
    ret

fat_read_file:
    ; Reads a file from a FAT12 filesystem.
    ; For now, it just reads the boot sector.
    ; returns: carry flag set on error

    cli ; Disable interrupts

    ; Read boot sector (LBA 0)
    mov eax, 0
    mov edi, boot_sector
    call ata_read_sector

    sti ; Re-enable interrupts

    jc .error

    clc ; Clear carry flag to indicate success
    ret

.error:
    sti ; Make sure interrupts are re-enabled on error
    stc ; Set carry flag to indicate error
    ret

fat_write_file:
    ; Placeholder for writing a file to a FAT12 filesystem.
    ; This is more complex than reading and would involve:
    ; 1. Finding an empty directory entry.
    ; 2. Finding free clusters in the FAT.
    ; 3. Writing the file data to the clusters.
    ; 4. Updating the FAT to create a cluster chain.
    ; 5. Updating the directory entry with file info.
    ret

print_hex:
    ; Prints a 32-bit hex value in eax to the screen.
    ; edi: screen position
    pushad
    mov ebx, 0xb8000
    add ebx, edi
    mov ecx, 8
.loop:
    rol eax, 4

    ; copy the low 4 bits of eax to al
    push eax
    and al, 0x0F
    call to_hex_char
    ; al now has the character

    ; write it to screen
    mov [ebx], al

    pop eax

    add ebx, 2
    loop .loop
    popad
    ret

gdt_start:
    dd 0, 0
    dw 0xffff, 0, 0x9a00, 0x00cf
    dw 0xffff, 0, 0x9200, 0x00cf
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

idt_descriptor:
    dw 256 * 8 - 1
    dd idt

msg_prompt db '> ', 0
msg_loading_file db 'Attempting to load a file...', 0
ascii_art_line1 db '  ######  #####  #####  #####   ', 0
ascii_art_line2 db '  #    #  #   #  #   #  #   #  ', 0
ascii_art_line3 db '  #    #  #      #   #  #      ', 0
ascii_art_line4 db '  ######  #####  #   #  #####  ', 0
ascii_art_line5 db '  #           #  #   #      # ', 0
ascii_art_line6 db '  #       #   #  #   #  #   #  ', 0
ascii_art_line7 db '  #       #####  #####  #####   ', 0

scancode_map:
    db 0, 27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 8, 9
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 13, 0
    db 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0, '#'
    db 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0, '*', 0, ' ', 0
    times 128 - ($ - scancode_map) db 0

    db 0, 27, '!', '"', '£', '$', '%', '^', '&', '*', '(', ')', '_', '+', 8, 9
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 13, 0
    db 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '@', '~', 0, '~'
    db 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0, '*', 0, ' ', 0
    times 256 - ($ - scancode_map) db 0

section .bss

boot_sector:

    resb 512

cluster_buffer:

    resb 4096

shift_pressed: resb 1

idt:

    resb 256 * 8

stack_bottom:

    resb 4096

stack_top:






