
.section .boot
j _start

.section .text

.global _start
_start:

addi a0, x0, 0x68
li a1, 0x10000000
sb a0, (a1)


la sp, __stack_top

.global main2
call main2

ebreak

loop:
j loop

.global std_print
std_print:
  li t0, 0x10000000
_std_print_loop:
  lb t1, 0(a0)
  beq t1, zero, _std_print_end
  sb t1, 0(t0)
  addi a0, a0, 1
  j _std_print_loop
_std_print_end:
  li t1, 13
  sb t1, 0(t0)
  li t1, 10
  sb t1, 0(t0)
  ret
