bits 16
org 0x8000

start_stage2:
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

    call pic_remap
    call idt_setup
    lidt [idt_descriptor]
    sti

    mov edi, 0xb8000
    mov ecx, 80 * 25
    mov al, ' '
    mov ah, 0x17
    rep stosw

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

cli_main:
    mov edi, (14 * 80 + 0) * 2
    mov esi, msg_prompt
    call print_string_pm

    ; Example of how to call the fat_read_file function
    ; We would need to pass a filename, and a buffer to load the file into.
    ; For now, we just call the placeholder.
    mov edi, (15 * 80 + 0) * 2
    mov esi, msg_loading_file
    call print_string_pm
    call fat_read_file

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

fat_read_file:
    ; Placeholder for reading a file from a FAT12 filesystem.
    ; This would involve:
    ; 1. Reading the boot sector to get filesystem info.
    ; 2. Finding the root directory.
    ; 3. Searching the root directory for the file.
    ; 4. Finding the first cluster of the file.
    ; 5. Following the cluster chain in the FAT.
    ; 6. Reading the file's data from the data region.
    ;
    ; This requires a disk driver to read sectors from the disk,
    ; as we are in protected mode and cannot use BIOS interrupts.
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
ascii_art_line3 db '  #    #  #   #  #   #  #      ', 0
ascii_art_line4 db '  ######  #####  #   #  #####  ', 0
ascii_art_line5 db '  #       #   #  #   #      # ', 0
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