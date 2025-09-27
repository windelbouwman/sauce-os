
SLANG_COMPILER=../build/compiler5
BUILDDIR=build

all: ${BUILDDIR} ${BUILDDIR}/kernel.elf

${BUILDDIR}:
	mkdir -p ${BUILDDIR}

myos.iso: ${BUILDDIR}/kernel.elf grub.cfg
	mkdir -p isodir/boot/grub
	cp ${BUILDDIR}/kernel.elf isodir/boot/kernel.bin
	cp grub.cfg isodir/boot/grub/grub.cfg
	grub-mkrescue -o myos.iso isodir

${BUILDDIR}/kernel.elf: ${BUILDDIR}/boot.o ${BUILDDIR}/kernel.o ${BUILDDIR}/kernel2.o
	# Use LLD linker
	ld.lld ${BUILDDIR}/boot.o ${BUILDDIR}/kernel.o ${BUILDDIR}/kernel2.o -o ${BUILDDIR}/kernel.elf
	grub-file --is-x86-multiboot ${BUILDDIR}/kernel.elf

${BUILDDIR}/kernel.o: kernel.c
	gcc -m32 -ffreestanding -c -o ${BUILDDIR}/kernel.o kernel.c

${BUILDDIR}/boot.o: boot.asm
	nasm -f elf32 -o ${BUILDDIR}/boot.o boot.asm

.SUFFIXES: .slang
${BUILDDIR}/%.ll: %.slang
	${SLANG_COMPILER} -o $@ $<

clean:
	rm -rf ${BUILDDIR}
