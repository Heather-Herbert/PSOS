# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Run

```bash
./build_and_run.sh
```

This assembles both stages, creates a 1.44MB FAT12 floppy image (`psos.img`), writes the bootloader and stage2, then boots in QEMU. The image is attached to QEMU as an IDE hard disk (`if=ide`), because stage2's disk driver uses the primary ATA controller.

**Dependencies:** `nasm`, `dd`, `mkfs.fat`, `qemu-system-x86_64`

To mount `psos.img` for inspection:
```bash
sudo ./mount_floppy.sh
# Unmount with: sudo umount /tmp/floppy_mnt
```

## Architecture

PSOS is a two-stage x86 bootloader/OS written in NASM assembly, targeting a 1.44MB floppy disk image.

**Boot flow:**
1. **`boot.asm`** (16-bit real mode, loaded at `0x7C00`) — Contains a FAT12 BPB, queries the BIOS E820 memory map into `0x500` (a dword count, then 24-byte entries from `0x504`), uses BIOS `int 0x13` to read `STAGE2_SECTORS` sectors from disk into `0x8000`, then jumps to stage2.
2. **`stage2.asm`** (transitions 16→32-bit protected mode, loaded at `0x8000`) — Sets up GDT, zeroes `.bss`, remaps the PIC, sets up an IDT (CPU exception stubs plus a keyboard ISR), prints the E820 map, initialises the physical memory manager (`pmm_init`), then calls `cli_main`.

**Disk layout:** `config.inc` defines `STAGE2_SECTORS` (shared by both stages). Stage2 lives at LBA 1 to `STAGE2_SECTORS`, inside the FAT12 reserved region: the BPB's reserved sector count is `STAGE2_SECTORS + 1`, and `build_and_run.sh` passes the same value to `mkfs.fat -R`, so the FATs start after stage2. Stage2 fails to assemble if it grows past `STAGE2_SECTORS * 512` bytes.

**Key subsystems in `stage2.asm`:**
- **Protected mode setup**: GDT with null/code/data descriptors; flat 32-bit memory model
- **PIC remapping**: Master PIC remapped to IRQ 0x20–0x27, slave to 0x28–0x2F; only IRQ1 (keyboard) unmasked
- **IDT**: Vectors 0–31 point to 8-byte `exception_stubs` that push the vector number; `exception_common` prints `CPU EXCEPTION <vector>` on row 24 and halts (full register dump is issue #20). Keyboard handler at entry 0x21; scancode map supports shift (UK layout, `£` = CP437 `0x9C`)
- **VGA text mode**: Direct writes to `0xB8000`; color attribute `0x17` (white on blue)
- **ATA PIO**: `ata_read_sector` / `ata_write_sector` use LBA28 via the primary ATA controller (ports `0x1F0–0x1F7`); poll BSY/DRQ with timeout via countdown loop; carry flag signals error
- **Physical memory manager**: bitmap frame allocator, one bit per 4 KB frame over the whole 32-bit address space (set = in use). `pmm_init` frees the usable (type 1) E820 regions, then marks non-usable regions and everything from address 0 to `bss_end` (IVT/BDA, E820 map, kernel, bitmap, stack) as used; memory above 4 GB is ignored. `pmm_alloc_frame` returns the lowest free frame's physical address in `eax`, or 0 with CF set on OOM. `pmm_free_frame` takes the address in `eax`; CF set on a double free or an address below `bss_end`. It cannot tell a reserved frame from an allocated one, so only pass it addresses that came from `pmm_alloc_frame`. The free frame count is printed on row 16
- **FAT12**: `fat_read_file` currently reads the boot sector (LBA 0) into `boot_sector` buffer; `fat_write_file` is a stub
- **Self-tests** (`run_tests`): check the BPB read from disk, and do a write/read-back test on `TEST_WRITE_LBA` (the last sector of the disk), restoring its original contents afterwards; also an alloc/free test of the frame allocator (`test_pmm`, result on row 23)

**Memory layout (stage2):**
| Symbol | Purpose |
|--------|---------|
| `bss_start`/`bss_end` | Bounds of `.bss`, zeroed at protected-mode entry |
| `boot_sector` | 512-byte buffer for BPB/boot sector read via ATA |
| `cluster_buffer` | 4 KB scratch buffer for disk I/O tests |
| `idt` | 256 × 8-byte IDT |
| `pmm_free_count` | Number of free frames |
| `pmm_hint` | Index of the first bitmap dword that may have a free bit |
| `pmm_bitmap` | 128 KB frame bitmap (1 bit per 4 KB frame, 4 GB) |
| `stack_bottom/top` | 4 KB stack |

## Conventions

- All assembly uses NASM syntax (`-f bin` flat binary output)
- Carry flag (`CF`) is the standard return convention for error signaling
- `print_string_pm` prints a null-terminated string; `edi` = VGA offset (in bytes from `0xB8000`), `esi` = string pointer
- VGA position formula: `(row * 80 + col) * 2`
- The `fat12_bpb` struc in `stage2.asm` mirrors the BPB written in `boot.asm`
- NASM has no backslash escapes in `'...'` strings: write an apostrophe as `"'"`, and write non-ASCII characters as CP437 byte values, not UTF-8 literals
