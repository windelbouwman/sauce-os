
run: tst.elf
	qemu-system-riscv32 -machine virt -cpu rv32 -bios none -kernel tst.elf

tst.elf: tst.o rv.ld
	riscv32-elf-ld -T rv.ld tst.o -o tst.elf

tst.o: tst.asm
	riscv32-elf-as -march=rv32im tst.asm -o tst.o
