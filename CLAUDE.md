# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Run

```bash
./build_and_run.sh
```

This assembles both stages, creates a 1.44MB FAT12 floppy image (`psos.img`), writes the bootloader and stage2, then boots in QEMU.

**Dependencies:** `nasm`, `dd`, `mkfs.fat`, `qemu-system-x86_64`

To mount `floppy.img` for inspection:
```bash
sudo ./mount_floppy.sh
# Unmount with: sudo umount /tmp/floppy_mnt
```

## Architecture

PSOS is a two-stage x86 bootloader/OS written in NASM assembly, targeting a 1.44MB floppy disk image.

**Boot flow:**
1. **`boot.asm`** (16-bit real mode, loaded at `0x7C00`) — Contains a FAT12 BPB, uses BIOS `int 0x13` to read 4 sectors from disk into `0x8000`, then jumps to stage2.
2. **`stage2.asm`** (transitions 16→32-bit protected mode, loaded at `0x8000`) — Sets up GDT, remaps the PIC, sets up an IDT with a keyboard ISR, then calls `cli_main`.

**Key subsystems in `stage2.asm`:**
- **Protected mode setup**: GDT with null/code/data descriptors; flat 32-bit memory model
- **PIC remapping**: Master PIC remapped to IRQ 0x20–0x27, slave to 0x28–0x2F; only IRQ1 (keyboard) unmasked
- **IDT / Keyboard ISR**: Single handler at IDT entry 0x21; scancode map supports shift (UK layout)
- **VGA text mode**: Direct writes to `0xB8000`; color attribute `0x17` (white on blue)
- **ATA PIO**: `ata_read_sector` / `ata_write_sector` use LBA28 via the primary ATA controller (ports `0x1F0–0x1F7`); poll BSY/DRQ with timeout via countdown loop; carry flag signals error
- **FAT12**: `fat_read_file` currently reads the boot sector (LBA 0) into `boot_sector` buffer; `fat_write_file` is a stub

**Memory layout (stage2):**
| Symbol | Purpose |
|--------|---------|
| `boot_sector` | 512-byte buffer for BPB/boot sector read via ATA |
| `cluster_buffer` | 4 KB scratch buffer for disk I/O tests |
| `idt` | 256 × 8-byte IDT |
| `stack_bottom/top` | 4 KB stack |

## Conventions

- All assembly uses NASM syntax (`-f bin` flat binary output)
- Carry flag (`CF`) is the standard return convention for error signaling
- `print_string_pm` prints a null-terminated string; `edi` = VGA offset (in bytes from `0xB8000`), `esi` = string pointer
- VGA position formula: `(row * 80 + col) * 2`
- The `fat12_bpb` struc in `stage2.asm` mirrors the BPB written in `boot.asm`
