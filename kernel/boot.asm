; Simple sort of boot assembly file

; See also:
; https://wiki.osdev.org/Bare_Bones

; Using NASM syntax here.

SECTION .multiboot

ALIGN_FLAG       EQU 1 <<0
MEMINFO_FLAG     EQU 1<<1
MULTIBOOT_FLAGS  EQU ALIGN_FLAG | MEMINFO_FLAG
MULTIBOOT_MAGIC  EQU 0x1BADB002
MULTIBOOT_CHECKSUM  EQU -(MULTIBOOT_MAGIC + MULTIBOOT_FLAGS)

ALIGN 4
DD MULTIBOOT_MAGIC
DD MULTIBOOT_FLAGS
DD MULTIBOOT_CHECKSUM

SECTION .bss
align 16
stack_bottom:
    RESB 16384
stack_top:

SECTION .text

GLOBAL _start
_start:
    ; prepare stack:
    MOV esp, stack_top

EXTERN kernel_main
    CALL kernel_main

endloop:
    HLT
    JMP endloop
