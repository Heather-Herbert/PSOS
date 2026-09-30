# PSOS
A toy 80x86 Operating System

PSOS is a two-stage bootloader and small kernel written in NASM assembly.
It boots from a 1.44MB FAT12 disk image, switches to 32-bit protected mode,
and currently:

- prints the BIOS E820 memory map
- reads key presses (UK layout) through a keyboard interrupt handler
- reads and writes disk sectors with ATA PIO
- reports CPU exceptions on screen instead of rebooting

## Building and running

You need `nasm`, `dd`, `mkfs.fat` (dosfstools) and `qemu-system-x86_64`.

```bash
./build_and_run.sh
```

See [CLAUDE.md](CLAUDE.md) for the architecture and memory layout.
