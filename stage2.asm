bits 16
org 0x8000

%include "config.inc"

start_stage2:
    ; Ensure DS=0 so that lgdt reads the GDT descriptor from the correct
    ; physical address. If DS is non-zero the CPU loads a garbage GDTR and
    ; the subsequent far jump triple-faults.
    xor ax, ax
    mov ds, ax

    ; Real-mode breadcrumb: confirm stage2 is actually loaded and running.
    ; GS is still 0xB800 from boot.asm (never cleared in stage2), so
    ; [GS:col*2] writes directly into the VGA text buffer without touching DS.
    mov byte [gs:5*2],   '5'    ; col 5 = stage2 reached real-mode entry
    mov byte [gs:5*2+1], 0x4F   ; white on red, same as boot.asm trace chars

    cli
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, 0x1
    mov cr0, eax
    jmp 0x08:protected_mode

; Write a single VGA character (white on blue, 0x1F) directly via a flat
; DS write. Only safe after DS has been loaded with the flat descriptor.
; col is a byte column index; the byte offset is col*2.
%macro pm_trace 2       ; pm_trace char, col
    mov byte [0xb8000 + %2 * 2],     %1
    mov byte [0xb8000 + %2 * 2 + 1], 0x1F
%endmacro

bits 32
protected_mode:
    mov ax, 0x10
    mov ds, ax          ; flat data segment — now safe to write anywhere
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; .bss is not part of the loaded image, so it holds whatever was in RAM.
    ; Zero it (IDT, shift state, buffers, stack) before anything uses it.
    ; No stack is needed here, so this runs before ESP is set.
    mov edi, bss_start
    mov ecx, bss_end - bss_start
    xor eax, eax
    cld
    rep stosb

    mov esp, stack_top
    pm_trace 'A', 10    ; col 10: segments + stack set up

    call pic_remap
    pm_trace 'B', 11    ; col 11: PIC remapped

    call idt_setup
    lidt [idt_descriptor]
    pm_trace 'C', 12    ; col 12: IDT loaded

    sti
    pm_trace 'D', 13    ; col 13: interrupts enabled

    mov edi, 0xb8000
    mov ecx, 80 * 25
    mov al, ' '
    mov ah, 0x17
    rep stosw

    call print_e820_map
    call pmm_init

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
    ; Loop: each interrupt (e.g. a key press) wakes the CPU from hlt,
    ; and without the jmp it would run on into the data below.
    hlt
    jmp halt

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

; Scratch sector for the write test: the last sector of the 1.44MB disk.
; It is in the FAT12 data area, well clear of the boot sector, stage2 and
; both FATs, and its original contents are restored after the test.
TEST_WRITE_LBA equ 2879

test_disk_write:
    ; Test writing to disk.
    ; 1. Read the scratch sector into cluster_buffer.
    ; 2. Save its first dword, replace it with a test pattern.
    ; 3. Write the sector.
    ; 4. Clear the buffer and read the sector back.
    ; 5. Verify the pattern.
    ; 6. Put the original dword back and rewrite the sector.
    push edi                ; VGA position for the result message

    ; Step 1: Read the scratch sector
    mov eax, TEST_WRITE_LBA
    mov edi, cluster_buffer
    call ata_read_sector
    jc .fail

    ; Step 2: Save the original first dword, then modify it
    push dword [cluster_buffer]
    mov dword [cluster_buffer], 0xDEADBEEF

    ; Step 3: Write the sector
    mov eax, TEST_WRITE_LBA
    mov esi, cluster_buffer
    call ata_write_sector
    jc .fail_saved          ; write may have partly happened; still restore

    ; Step 4: Clear the buffer and read the sector again
    mov dword [cluster_buffer], 0
    mov eax, TEST_WRITE_LBA
    mov edi, cluster_buffer
    call ata_read_sector
    jc .fail_saved

    ; Step 5: Verify
    cmp dword [cluster_buffer], 0xDEADBEEF
    jne .fail_saved

    ; Step 6: Restore the original contents
    pop dword [cluster_buffer]
    mov eax, TEST_WRITE_LBA
    mov esi, cluster_buffer
    call ata_write_sector
    jc .fail

    pop edi
    mov esi, msg_test_write_pass
    call print_string_pm
    ret

.fail_saved:
    ; Best-effort restore of the original dword; the rest of the buffer
    ; still holds the sector's original bytes from step 1.
    pop dword [cluster_buffer]
    mov eax, TEST_WRITE_LBA
    mov esi, cluster_buffer
    call ata_write_sector
.fail:
    pop edi
    mov esi, msg_test_write_fail
    call print_string_pm
    ret

run_tests:
    call fat_read_file
    jc .error               ; check CF before anything else can clobber it

    ; Print the first byte of the boot sector
    movzx eax, byte [boot_sector]
    mov edi, (21 * 80 + 0) * 2 ; New line
    call print_hex

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
    ; Point vectors 0-31 (CPU exceptions) at their stubs so a fault
    ; reports itself instead of triple-faulting through an empty IDT.
    xor ecx, ecx
.exc_loop:
    mov eax, ecx
    shl eax, 3                      ; stubs are EXC_STUB_SIZE (8) bytes apart
    add eax, exception_stubs
    mov word [idt + ecx * 8], ax
    shr eax, 16
    mov word [idt + ecx * 8 + 6], ax
    mov word [idt + ecx * 8 + 2], 0x08
    mov byte [idt + ecx * 8 + 5], 0x8E
    inc ecx
    cmp ecx, 32
    jb .exc_loop

    mov eax, keyboard_isr
    mov word [idt + 0x21 * 8], ax
    shr eax, 16
    mov word [idt + 0x21 * 8 + 6], ax
    mov word [idt + 0x21 * 8 + 2], 0x08
    mov byte [idt + 0x21 * 8 + 5], 0x8E
    ret

; One fixed-size stub per CPU exception vector 0-31. Each pushes its
; vector number and jumps to the common handler, so stub n lives at
; exception_stubs + n * EXC_STUB_SIZE and idt_setup needs no table.
EXC_STUB_SIZE equ 8
exception_stubs:
%assign vec 0
%rep 32
    push byte vec           ; 2 bytes; + 5-byte near jmp fits in 8
    jmp exception_common
    times exception_stubs + (vec + 1) * EXC_STUB_SIZE - $ db 0x90
%assign vec vec + 1
%endrep

; Minimal fatal exception handler: print the vector number on the bottom
; row and halt. (A full register dump is tracked in issue #20.)
exception_common:
    cli
    mov edi, (24 * 80 + 0) * 2
    mov esi, msg_exception
    call print_string_pm
    pop eax                 ; vector number pushed by the stub
    call print_hex
.hang:
    hlt
    jmp .hang

msg_exception db 'CPU EXCEPTION ', 0

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
; Rows 0..(count-1), format: "BASE=XXXXXXXXXXXXXXXX LEN=XXXXXXXXXXXXXXXX TYPE=XXXXXXXX"
; Clobbers: eax, ebx, ecx, edx, esi, edi
print_e820_map:
    mov ecx, [E820_COUNT]
    test ecx, ecx
    jz .done

    mov ebx, E820_ENTRIES   ; pointer to current entry
    xor edx, edx            ; row counter

.entry_loop:
    ; print_string_pm clobbers EBX (sets it to 0xb8000), so push/pop it
    ; around every call to keep the entry pointer intact.
    ; print_hex uses pushad/popad so it preserves EBX automatically.
    ; edi is the VGA byte offset; print_string_pm advances it per char,
    ; but print_hex does not — manually add 8*2 after each print_hex.

    mov edi, edx
    imul edi, 80 * 2        ; start of row

    push ebx
    mov esi, msg_e820_base
    call print_string_pm    ; edi now past "BASE="
    pop ebx
    mov eax, [ebx + 4]      ; base high 32 bits
    call print_hex
    add edi, 8 * 2
    mov eax, [ebx]          ; base low 32 bits
    call print_hex
    add edi, 8 * 2          ; advance past 16 hex digits total

    push ebx
    mov esi, msg_e820_len
    call print_string_pm    ; edi now past " LEN="
    pop ebx
    mov eax, [ebx + 12]     ; length high 32 bits
    call print_hex
    add edi, 8 * 2
    mov eax, [ebx + 8]      ; length low 32 bits
    call print_hex
    add edi, 8 * 2          ; advance past 16 hex digits total

    push ebx
    mov esi, msg_e820_type
    call print_string_pm    ; edi now past " TYPE="
    pop ebx
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

; --- Physical memory manager: bitmap frame allocator ---
; One bit per 4 KB frame over the whole 32-bit address space (set = in use).
; Frame n covers physical addresses n * 4096 .. n * 4096 + 4095.
PMM_FRAME_SHIFT   equ 12
PMM_FRAME_SIZE    equ 1 << PMM_FRAME_SHIFT
PMM_FRAMES        equ 1 << (32 - PMM_FRAME_SHIFT)
PMM_BITMAP_DWORDS equ PMM_FRAMES / 32

; pmm_init
; Builds the frame bitmap from the E820 map left by the bootloader.
; Everything starts out as used; only frames lying wholly inside a usable
; (type 1) entry are freed. Non-usable entries are then marked used again
; in a second pass, because E820 entries may overlap. Finally everything
; from address 0 to the end of .bss is reserved: the real-mode IVT/BDA,
; the E820 map itself, and the kernel image, bitmap and stack.
; Memory above 4 GB cannot be addressed and is ignored.
; Preserves all registers.
pmm_init:
    pushad

    mov edi, pmm_bitmap
    mov ecx, PMM_BITMAP_DWORDS
    mov eax, 0xFFFFFFFF
    cld
    rep stosd
    mov dword [pmm_free_count], 0
    mov dword [pmm_hint], 0

    ; Pass 1: free usable regions, rounded inwards to whole frames.
    mov esi, E820_ENTRIES
    mov ebx, [E820_COUNT]
    test ebx, ebx
    jz .reserve_kernel
.usable_loop:
    cmp dword [esi + 16], 1
    jne .usable_next
    mov ecx, PMM_FRAME_SIZE - 1     ; round the start up
    xor edi, edi                    ; round the end down
    call pmm_e820_range
    call pmm_clear_range
.usable_next:
    add esi, 24
    dec ebx
    jnz .usable_loop

    ; Pass 2: mark everything else used, rounded outwards.
    mov esi, E820_ENTRIES
    mov ebx, [E820_COUNT]
.reserved_loop:
    cmp dword [esi + 16], 1
    je .reserved_next
    xor ecx, ecx                    ; round the start down
    mov edi, PMM_FRAME_SIZE - 1     ; round the end up
    call pmm_e820_range
    call pmm_set_range
.reserved_next:
    add esi, 24
    dec ebx
    jnz .reserved_loop

.reserve_kernel:
    ; Frame 0 is always inside this range, so pmm_alloc_frame can never
    ; hand out address 0 and can use it to mean "out of memory".
    xor eax, eax
    mov edx, bss_end + PMM_FRAME_SIZE - 1
    shr edx, PMM_FRAME_SHIFT
    call pmm_set_range

    popad
    ret

; pmm_e820_range
; Converts an E820 entry to a frame range.
; esi: E820 entry
; ecx: bias added to the base before rounding down (0 or PMM_FRAME_SIZE - 1)
; edi: bias added to the end before rounding down (0 or PMM_FRAME_SIZE - 1)
; returns: eax = first frame, edx = end frame (exclusive), both clamped
;          to PMM_FRAMES
pmm_e820_range:
    mov eax, [esi]
    mov edx, [esi + 4]
    add eax, ecx
    adc edx, 0
    call pmm_addr_to_frame
    push eax

    mov eax, [esi]
    mov edx, [esi + 4]
    add eax, [esi + 8]
    adc edx, [esi + 12]
    add eax, edi
    adc edx, 0
    call pmm_addr_to_frame
    mov edx, eax
    pop eax
    ret

; pmm_addr_to_frame
; edx:eax: 64-bit physical address
; returns: eax = frame number, clamped to PMM_FRAMES for addresses >= 4 GB
pmm_addr_to_frame:
    test edx, edx
    jnz .clamp
    shr eax, PMM_FRAME_SHIFT
    ret
.clamp:
    mov eax, PMM_FRAMES
    ret

; pmm_clear_range / pmm_set_range
; Mark frames eax..edx-1 free / used, keeping pmm_free_count in step.
; Does nothing if eax >= edx. Clobbers eax.
pmm_clear_range:
.loop:
    cmp eax, edx
    jae .done
    btr [pmm_bitmap], eax
    jnc .next                       ; was already free
    inc dword [pmm_free_count]
.next:
    inc eax
    jmp .loop
.done:
    ret

pmm_set_range:
.loop:
    cmp eax, edx
    jae .done
    bts [pmm_bitmap], eax
    jc .next                        ; was already used
    dec dword [pmm_free_count]
.next:
    inc eax
    jmp .loop
.done:
    ret

; pmm_alloc_frame
; Allocates the lowest free 4 KB frame. Its contents are not cleared.
; returns: eax = physical address of the frame, carry flag clear
;          eax = 0 and carry flag set when out of memory
; Preserves all other registers.
pmm_alloc_frame:
    push ecx
    push edi

    ; pmm_hint is the index of the first bitmap dword that can still have
    ; a free bit, so full dwords below it are not rescanned every call.
    mov edi, [pmm_hint]
    mov ecx, PMM_BITMAP_DWORDS
    sub ecx, edi
    jz .oom
    lea edi, [pmm_bitmap + edi * 4]
    mov eax, 0xFFFFFFFF
    cld
    repe scasd
    je .oom                         ; every remaining dword is full

    sub edi, 4                      ; back to the dword with a free bit
    mov eax, [edi]
    not eax
    bsf eax, eax                    ; lowest clear bit
    bts [edi], eax
    dec dword [pmm_free_count]

    sub edi, pmm_bitmap             ; byte offset of that dword
    mov ecx, edi
    shr ecx, 2
    mov [pmm_hint], ecx
    lea eax, [eax + edi * 8]        ; frame number
    shl eax, PMM_FRAME_SHIFT

    pop edi
    pop ecx
    clc
    ret

.oom:
    mov dword [pmm_hint], PMM_BITMAP_DWORDS
    xor eax, eax
    pop edi
    pop ecx
    stc
    ret

; pmm_free_frame
; Returns a frame to the allocator.
; eax: physical address inside the frame (as returned by pmm_alloc_frame)
; returns: carry flag set, and nothing changed, if the frame is already
;          free or lies in the kernel's own memory below bss_end
; Preserves all registers.
pmm_free_frame:
    push eax
    cmp eax, bss_end
    jb .error
    shr eax, PMM_FRAME_SHIFT
    btr [pmm_bitmap], eax
    jnc .error                      ; double free
    inc dword [pmm_free_count]

    shr eax, 5                      ; bitmap dword holding this frame
    cmp eax, [pmm_hint]
    jae .done
    mov [pmm_hint], eax
.done:
    pop eax
    clc
    ret

.error:
    pop eax
    stc
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
    ; NASM has no backslash escapes in '...' strings, so the apostrophe is
    ; written as "'" (a single-quoted '\'' would swallow the rest of the line).
    db 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", '`', 0, '#'
    db 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0, '*', 0, ' ', 0
    times 128 - ($ - scancode_map) db 0

    ; 0x9C is the pound sign in VGA code page 437 (a literal '£' in this
    ; UTF-8 source would assemble to two bytes and shift the table).
    db 0, 27, '!', '"', 0x9C, '$', '%', '^', '&', '*', '(', ')', '_', '+', 8, 9
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 13, 0
    db 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '@', '~', 0, '~'
    db 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0, '*', 0, ' ', 0
    times 256 - ($ - scancode_map) db 0

%if ($ - $$) > STAGE2_SECTORS * 512
    %error "stage2 is larger than STAGE2_SECTORS; raise it in config.inc"
%endif

section .bss

bss_start:

boot_sector:

    resb 512

cluster_buffer:

    resb 4096

shift_pressed: resb 1

idt:

    resb 256 * 8

alignb 4

pmm_free_count: resd 1      ; number of free frames

pmm_hint: resd 1            ; first bitmap dword that may have a free bit

pmm_bitmap:

    resd PMM_BITMAP_DWORDS

stack_bottom:

    resb 4096

stack_top:

bss_end:
