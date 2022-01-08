#!/bin/bash

set -eu

# Via a grub iso (usable on real hardware!)
# make myos.iso
# qemu-system-i386 -cdrom myos.iso

# Directly load kernel (without grub):
make
qemu-system-i386 -kernel build/kernel.elf

