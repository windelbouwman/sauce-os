
.global _start
.section .text

_start:

addi a0, x0, 0x68
li a1, 0x10000000
sb a0, (a1)

addi a0, x0, 0x65
sb a0, (a1)

addi a0, x0, 0x6c
sb a0, (a1)

addi a0, x0, 0x6f
sb a0, (a1)

loop:
j loop
